//+------------------------------------------------------------------+
//|                                              LREA-HFT.mq4        |
//|                    Copyright 2024, MinoDrama Software Crops      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property strict

// Input parameters
input double RiskPercentage = 1.0;    // The percentage of the account balance to risk
input int StopLossPips = 5;           // Stop loss in pips
input int TrailingStop = 50;          // Trailing stop in pips
input double TrailStart = 5.0;        // Distance from the open price to start trailing
input int MaxOpenTrades = 5;          // Maximum number of open trades
input int RSIPeriod = 5;              // Period for RSI
input double RSIOverboughtLevel = 70; // RSI overbought level
input double RSIOversoldLevel = 30;   // RSI oversold level
input int MAPeriod = 5;               // Period for Moving Average
input int MAShift = 0;                // Shift for Moving Average
double TargetProfitUSD = 0.15;        // Target profit in USD

// Global variables
double LotSize; // Calculated lot size based on risk percentage

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Calculate lot size based on risk percentage and enforce maximum lot size of 0.01
   LotSize = MathMin(RiskPercentageToLotSize(RiskPercentage), 0.01);

   // Additional initialization code (if necessary)
   // ...

   return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Deinitialization code (if necessary)
   // ...
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Implement high-frequency trading logic
   if (IsHFTEntryConditionMet())
   {
      // Determine trade direction (buy or sell)
      bool isBuy = (Close[0] > iMA(Symbol(), PERIOD_M5, MAPeriod, MAShift, MODE_SMA, PRICE_CLOSE, 0));

      // Check maximum open trades
      if (CountOpenTrades() >= MaxOpenTrades)
         return;

      int tradeType = isBuy ? OP_BUY : OP_SELL;

      // Open a trade with calculated lot size
      // Open a trade with calculated lot size
      int ticket = OrderSend(Symbol(), tradeType, LotSize, isBuy ? Ask : Bid, 3, 0, 0, "LREA HFT by MinoDrama Software Crops", 0, 0, isBuy ? clrBlue : clrRed);

      // Set stop loss and take profit levels
      double stopLossLevel = isBuy ? Ask - StopLossPips * Point : Bid + StopLossPips * Point;
      double takeProfitLevel = CalculateTakeProfitLevel(isBuy);

      if (ticket > 0)
      {
         bool modifyResult = OrderModify(ticket, OrderOpenPrice(), stopLossLevel, takeProfitLevel, 0, clrNONE);
         if (!modifyResult)
         {
            Print("OrderModify failed. Error code: ", GetLastError());
         }
      }
   }

   // Check for open trades and apply trailing stop
   ApplyTrailingStop(TrailStart, TrailingStop);

   // Check for open trades and close them at target profit
   CloseTradesAtProfit();
}

//+------------------------------------------------------------------+
//| Apply trailing stop to open trades                                |
//+------------------------------------------------------------------+
void ApplyTrailingStop(double trailStart, int trailingStop)
{
   double breakevenTrigger = (2 + MarketInfo(Symbol(), MODE_SPREAD)) * Point; // Adjust this for 2 pips + spread

   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (OrderSelect(i, SELECT_BY_POS) && OrderSymbol() == Symbol() && OrderMagicNumber() == 0)
      {
         double currentProfit = OrderProfit();
         double currentOpenPrice = OrderOpenPrice();
         double currentStopLoss = OrderStopLoss();

         // Check if profit is enough to move stop loss to breakeven
         if (currentProfit >= breakevenTrigger)
         {
            double newStopLoss = currentOpenPrice;

            // Apply trailing stop if profit exceeds trailStart
            if (currentProfit > trailStart * Point)
            {
               newStopLoss = OrderType() == OP_BUY ? newStopLoss + trailingStop * Point : newStopLoss - trailingStop * Point;
            }

            // Ensure new SL is more favorable than current SL
            if ((OrderType() == OP_BUY && newStopLoss > currentStopLoss) ||
                (OrderType() == OP_SELL && newStopLoss < currentStopLoss))
            {
               if (OrderModify(OrderTicket(), OrderOpenPrice(), newStopLoss, OrderTakeProfit(), 0, clrNONE))
               {
                  // OrderModify successful
               }
               else
               {
                  Print("OrderModify failed. Error code: ", GetLastError());
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close trades when the specified profit is reached                |
//+------------------------------------------------------------------+
void CloseTradesAtProfit()
{
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (OrderSelect(i, SELECT_BY_POS) && OrderSymbol() == Symbol() && OrderMagicNumber() == 0)
      {
         double profit = OrderProfit();
         if (profit >= TargetProfitUSD)
         {
            bool closeResult = OrderClose(OrderTicket(), OrderLots(), OrderType() == OP_BUY ? Bid : Ask, 3, clrNONE);
            if (!closeResult)
            {
               // Handle the error if OrderClose fails
               Print("Error closing order: ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if HFT entry conditions are met                            |
//+------------------------------------------------------------------+
bool IsHFTEntryConditionMet()
{
   // Calculate RSI
   double rsi = iRSI(Symbol(), PERIOD_M5, RSIPeriod, PRICE_CLOSE, 0);

   // Define entry conditions
   bool isBuyCondition = (rsi < RSIOverboughtLevel);
   bool isSellCondition = (rsi > RSIOversoldLevel);

   return isBuyCondition || isSellCondition;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage                      |
//+------------------------------------------------------------------+
double RiskPercentageToLotSize(double riskPercentage)
{
   double balance = AccountBalance();
   double risk = balance * riskPercentage / 100;
   double pipValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double lotSize = risk / (StopLossPips * pipValue);

   // Adjust lot size based on the minimum lot size and maximum lot size allowed
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   lotSize = MathMax(minLot, MathMin(lotSize, maxLot));

   return NormalizeDouble(lotSize, int(1 / MarketInfo(Symbol(), MODE_LOTSTEP)));
}

//+------------------------------------------------------------------+
//| Calculate take profit level based on target profit in USD        |
//+------------------------------------------------------------------+
double CalculateTakeProfitLevel(bool isBuy)
{
   double pipValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double pipsToTarget = TargetProfitUSD / pipValue;
   double currentPrice = isBuy ? Ask : Bid;
   double takeProfitLevel = isBuy ? currentPrice + pipsToTarget * Point : currentPrice - pipsToTarget * Point;

   return NormalizeDouble(takeProfitLevel, Digits);
}

//+------------------------------------------------------------------+
//| Count the number of open trades                                   |
//+------------------------------------------------------------------+
int CountOpenTrades()
{
   int count = 0;

   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (OrderSelect(i, SELECT_BY_POS) && OrderSymbol() == Symbol())
      {
         count++;
      }
   }

   return count;
}