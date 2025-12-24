# ============================================================
# Youth Employment Rate (15–24) — Time Series Analysis (TR)
# SARIMA + ETS comparison (portfolio script)
# ============================================================

# ---- Libraries ----
library(readxl)
library(dplyr)
library(stringr)
library(lubridate)
library(tidyr)
library(forecast)
library(astsa)


# ---- Data import ----
# IMPORTANT: put the .xls file in your repo (data/ folder) OR update the path
path <- "data/temel_isgucu_gostergeleri_15_24.xls"
data_raw <- read_excel(path, sheet = "Tablo", col_names = FALSE)

# ---- Cleaning ----
df <- data_raw %>%
  slice(5:n()) %>%  # data starts after header rows
  rename(Year = ...1, Month = ...2) %>%
  mutate(
    Year = as.integer(Year),
    Year = tidyr::fill(., Year, .direction = "down")$Year
  ) %>%
  filter(!is.na(Month))

# Month parser (expects something like "2020 - January" style)
month_num <- function(x) {
  x <- as.character(x)
  eng <- str_split_fixed(x, "-", 2)[, 2]
  eng <- str_trim(eng)
  eng <- str_split_fixed(eng, " ", 2)[, 1]

  months <- c("January","February","March","April","May","June",
              "July","August","September","October","November","December")
  match(eng, months)
}

df <- df %>%
  mutate(
    MonthNum = month_num(Month),
    Date = as.Date(paste(Year, MonthNum, "01", sep = "-")),
    EmploymentRate = as.numeric(...9),
    EmploymentRate = ifelse(EmploymentRate >= 0 & EmploymentRate <= 100, EmploymentRate, NA)
  )

df_plot <- df %>% filter(!is.na(EmploymentRate))

# ---- PART 1: Plot raw series ----
png("outputs/raw_series.png", width = 1200, height = 800)
plot(df_plot$Date, df_plot$EmploymentRate,
     type = "l",
     main = "Youth (15–24) Employment Rate (%)",
     xlab = "Date",
     ylab = "Employment rate (%)")
dev.off()

# ---- PART 2: Create ts object + decomposition ----
df_ts <- df %>% filter(!is.na(EmploymentRate))

start_year  <- year(min(df_ts$Date))
start_month <- month(min(df_ts$Date))

y <- ts(df_ts$EmploymentRate,
        start = c(start_year, start_month),
        frequency = 12)

png("outputs/ts_plot.png", width = 1200, height = 800)
plot(y, main = "Youth (15–24) Employment Rate (%)")
dev.off()

png("outputs/decomp_additive.png", width = 1200, height = 800)
plot(decompose(y, type = "additive"))
dev.off()

png("outputs/decomp_multiplicative.png", width = 1200, height = 800)
plot(decompose(y, type = "multiplicative"))
dev.off()

# ---- TASK 3: Smoothing (MA + LOWESS) ----
x <- as.numeric(y)

ma <- stats::filter(x, rep(1/12, 12), sides = 2)

png("outputs/moving_average.png", width = 1200, height = 800)
plot(y, type="l",
     main="12-month Moving Average (Centered)",
     xlab="Time", ylab="Employment rate (%)")
lines(ma, lty=2)
dev.off()

t <- time(y)
lo <- lowess(t, x, f = 2/3)

png("outputs/lowess.png", width = 1200, height = 800)
plot(y, type="l",
     main="LOWESS Smoothing (f = 2/3)",
     xlab="Time", ylab="Employment rate (%)")
lines(lo$x, lo$y, lty=2)
dev.off()

# ---- TASK 4: SARIMA Identification ----
dx1    <- diff(x, 1)
dx12   <- diff(x, 12)
dx1_12 <- diff(dx1, 12)

png("outputs/acf_pacf_diffs.png", width = 1200, height = 1400)
par(mfrow=c(3,1))
acf2(dx1,    main="ACF/PACF: diff(x,1)")
acf2(dx12,   main="ACF/PACF: diff(x,12)")
acf2(dx1_12, main="ACF/PACF: diff(diff(x,1),12)")
par(mfrow=c(1,1))
dev.off()

# Candidate SARIMA models (astsa::sarima)
m1 <- sarima(x, 1,1,1, 0,1,1, 12)
m2 <- sarima(x, 0,1,1, 0,1,1, 12)
m3 <- sarima(x, 1,1,0, 0,1,1, 12)
m4 <- sarima(x, 1,1,1, 1,1,1, 12)

# Final selected model (your choice)
fit <- sarima(x, 1,1,1, 0,1,1, 12)

res <- as.numeric(fit$fit$residuals)
res <- res[!is.na(res)]

png("outputs/sarima_residual_acf.png", width = 1200, height = 800)
acf(res, main="Residual ACF (SARIMA)")
dev.off()

png("outputs/sarima_qqplot.png", width = 1200, height = 800)
qqnorm(res, main="Residuals Q-Q Plot (SARIMA)")
qqline(res)
dev.off()

bp <- Box.test(res, lag=24, type="Box-Pierce")
print(bp)

# ---- PART 5: Forecasting & ARIMA vs ETS comparison ----
h <- 12
n <- length(x)

train <- x[1:(n - h)]
test  <- x[(n - h + 1):n]

train_ts <- ts(train, frequency = 12)
test_ts  <- ts(test,  frequency = 12, start = tsp(train_ts)[2] + 1/12)

# SARIMA via forecast::Arima (same structure as selected)
fit_arima <- Arima(train_ts, order = c(1,1,1), seasonal = c(0,1,1))
fc_arima <- forecast(fit_arima, h = h)

# ETS
fit_ets <- ets(train_ts)
fc_ets  <- forecast(fit_ets, h = h)

# Accuracy
acc_arima <- accuracy(fc_arima, test_ts)
acc_ets   <- accuracy(fc_ets, test_ts)

cmp <- rbind(
  ARIMA = acc_arima[2, c("MAE","RMSE","MAPE")],
  ETS   = acc_ets[2, c("MAE","RMSE","MAPE")]
)
print(cmp)

# Save comparison table as csv 
write.csv(cmp, "outputs/model_comparison_metrics.csv", row.names = TRUE)

# Forecast plots
png("outputs/forecast_sarima_vs_actual.png", width = 1200, height = 800)
plot(fc_arima, main="Forecast Comparison: SARIMA vs Actual",
     xlab="Time", ylab="Employment rate (%)")
lines(test_ts, lty=1)
dev.off()

png("outputs/forecast_ets_vs_actual.png", width = 1200, height = 800)
plot(fc_ets, main="Forecast Comparison: ETS vs Actual",
     xlab="Time", ylab="Employment rate (%)")
lines(test_ts, lty=1)
dev.off()
