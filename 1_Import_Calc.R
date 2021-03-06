# Import and data cleansing

### Load packages and set options

options(scipen = 0, digits = 5) # set options to avoid scientific notation
options("getSymbols.warning4.0"=FALSE)
Sys.setenv(TZ="America/Chicago") # needs to be done in order to make sure, getSymbols works properly.
suppressPackageStartupMessages(library(googleVis))

library(googleVis)
library(ggplot2)
library(quantmod)
library(reshape2)
library(scales)
library(gridExtra)
library(Quandl)


### Import
try(getSymbols(c( "DJIA", "^GDAXI", "^FTSE", "^FCHI", "^SSMI", "^IBEX", "^SSEC", "^STI", "^MXX", "^N225", "^AORD", "RTS.RS", "^ATX", "^GSPTSE", "^HSI", "^BVSP", "^MERV"), warnings=FALSE))

indices.zoo <- merge(Ad(DJIA), Ad(AORD), Ad(ATX), Ad(BVSP), Ad(FCHI), Ad(FTSE),  Ad(GDAXI), Ad(GSPTSE), Ad(HSI), Ad(IBEX), Ad(MERV), Ad(MXX), Ad(N225), Ad(RTS.RS), Ad(SSEC), Ad(SSMI), Ad(STI))
colnames(indices.zoo) <- c("USA", "Australia", "Austria", "Brasil", "France", "United Kingdom",  "Germany", "Canada", "HongKong", "Spain", "Argentina", "Mexico", "Japan", "Russia", "China", "Switzerland", "Singapore")      
tail(indices.zoo)


getSymbols("^GSPC") #load S&P 500 data.
snp <- Ad(GSPC)

Sys.setenv(TZ="CET") # sets system time back to Europe; important for the deletion that follows

#--Download Russian data----------------------------
URL <- "http://moex.com/iss/history/engines/stock/markets/index/securities/RTSI.csv?iss.only=history&iss.json=extended&callback=JSON_CALLBACK&from=2015-01-01&till=2016-12-31&lang=en&limit=100&start=0&sort_order=TRADEDATE&sort_order_desc=desc"
download.file(URL, destfile="rtsi.csv")
rtsi <- read.csv(file="rtsi.csv", header=TRUE, skip=2, sep=";")
rtsi <- rtsi[,c("TRADEDATE", "CLOSE")] # drop irrelevant columns
library(lubridate)
rtsi$TRADEDATE <- ymd(rtsi$TRADEDATE) #convert to POSIXct
rtsi$TRADEDATE <- as.Date(rtsi$TRADEDATE) # convert to as.Date
ind <- data.frame(Date=index(indices.zoo$Russia),indices.zoo$Russia) # create new, temporary dataframe for Russia only
ind.m <- merge(x=ind, y=rtsi, by.x="Date", by.y="TRADEDATE", all.x=TRUE) # merge the Yahoo and the RTS data
ind.m$Russia[is.na(ind.m$Russia)] <- ind.m$CLOSE[is.na(ind.m$Russia)] # replace the NA data from yahoo with data from RTS
indices.zoo$Russia <- ind.m$Russia # add the new Russia data to the bigger data frame 
#--------


#---Download Italian data
#mib <- Quandl("YAHOO/INDEX_FTSEMIB_MI", type="xts", start=start(indices.zoo))
# or: https://www.quandl.com/api/v1/datasets/YAHOO/INDEX_FTSEMIB_MI.csv
# QUANDL seems instable, therefore we firts query Quandl. If that throws an error, we query yahoo.

italiandata <- new.env()

MIBfromQuandl <- function() {
  download.file("http://www.quandl.com/api/v1/datasets/YAHOO/INDEX_FTSEMIB_MI.csv", "MIB.csv", method="curl")
  mib <- read.csv("MIB.csv")
  mib$Date <- ymd(mib$Date)
  mib <- zoo(mib, order.by = mib$Date)[,-1]
  mib <- as.quantmod.OHLC(mib, col.names=c("Open", "High", "Low", "Close", "Volume", "Adjusted.Close")) 
  mib.zoo <-  Ad(mib)
}

MIBfromYahoo <- function() {
  getSymbols("FTSEMIB.MI", env = italiandata)
  mib.zoo <<-Ad(italiandata$FTSEMIB.MI)
  names(mib.zoo) <<- "Italy"
  print("Loading from Yahoo succesfull")
}


tryCatch(MIBfromQuandl(),
  error=function(e) MIBfromYahoo()) 

 
indices.zoo <- merge(indices.zoo, mib.zoo)
#------------

indices.zoo <- window(indices.zoo, start=as.Date("2007-01-01"), end=Sys.Date()-1) # delete current day, because it will contain NAs.

rm(list=setdiff(ls(), c("indices.zoo", "snp"))) # remove all raw data, just keep indices.zoo and the S&P Data

write.zoo(indices.zoo, file="/home/fibo/scripts/Boersentacho/indices_raw.csv", row.names=FALSE)
### Check missing data
#   check.df <- data.frame(is.na(data.frame(coredata(indices.zoo))))
#   check.df$Date <- index(indices.zoo)
#   check.m <- melt(check.df, id.vars="Date", variable.name="Country", value.name="Missing_Quote")
#   ggplot(data=subset(check.m)) + geom_tile(aes(x=Date, y=Country, fill=Missing_Quote)) + theme_minimal()

### treat NAs
indices.zoo <- na.approx(zoo(indices.zoo), na.rm=TRUE) # interpolation happens for NAs
indices.zoo <- na.locf(indices.zoo) # any remaining NAs are being replaced by simple "roll forward"

write.zoo(indices.zoo, file="/home/fibo/scripts/Boersentacho/indices_cleaned.csv", row.names=FALSE)


### calculate RSL
#RSL=Close/MovingAverage
mean.zoo <- rollapply(indices.zoo, width=27, FUN=mean, na.rm=T, align="right")
rsl.zoo <- indices.zoo / mean.zoo
rsl.gd.zoo <- rollapply(rsl.zoo, width=10, FUN=mean, na.rm=T, align="right") # we add a 10-day SMA
rsl.all.zoo <- zoo(rowMeans(rsl.gd.zoo), order.by=as.Date(index(rsl.gd.zoo)))
#plot(tail(rsl.all.zoo, 40), type="b")

write.zoo(rsl.gd.zoo, file="/home/fibo/scripts/Boersentacho/hbt.csv", row.names=FALSE)


### Save data
save(indices.zoo, rsl.gd.zoo, rsl.all.zoo, snp, file="/home/fibo/scripts/Boersentacho/Indices_Data.RData")

