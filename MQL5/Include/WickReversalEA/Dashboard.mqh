//+------------------------------------------------------------------+
//|                                                   Dashboard.mqh |
//| Painel visual no grafico: estado do EA, equity de referencia,   |
//| e o setup ativo de cada lado (compra/venda).                    |
//+------------------------------------------------------------------+
#property strict

#include <WickReversalEA/Defines.mqh>

#define WREA_DASH_PREFIX "WREA_DASH_"

class CWrDashboard
  {
private:
   long   m_chartId;
   string m_prefix;
   int    m_x;
   int    m_y;

   void CreateLabel(const string name,const int x,const int y,const string text,
                     const color clr,const int fontSize = 9)
     {
      string objName = m_prefix + name;
      if(ObjectFind(m_chartId, objName) < 0)
        {
         ObjectCreate(m_chartId, objName, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(m_chartId, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chartId, objName, OBJPROP_XDISTANCE, x);
         ObjectSetInteger(m_chartId, objName, OBJPROP_YDISTANCE, y);
         ObjectSetInteger(m_chartId, objName, OBJPROP_FONTSIZE, fontSize);
         ObjectSetString(m_chartId, objName, OBJPROP_FONT, "Consolas");
         ObjectSetInteger(m_chartId, objName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chartId, objName, OBJPROP_HIDDEN, true);
        }
      ObjectSetString(m_chartId, objName, OBJPROP_TEXT, text);
      ObjectSetInteger(m_chartId, objName, OBJPROP_COLOR, clr);
     }

   void CreateBackground(const int width,const int height)
     {
      string objName = m_prefix + "BG";
      if(ObjectFind(m_chartId, objName) < 0)
        {
         ObjectCreate(m_chartId, objName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(m_chartId, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chartId, objName, OBJPROP_XDISTANCE, m_x - 10);
         ObjectSetInteger(m_chartId, objName, OBJPROP_YDISTANCE, m_y - 10);
         ObjectSetInteger(m_chartId, objName, OBJPROP_XSIZE, width);
         ObjectSetInteger(m_chartId, objName, OBJPROP_YSIZE, height);
         ObjectSetInteger(m_chartId, objName, OBJPROP_BGCOLOR, C'18,18,17');
         ObjectSetInteger(m_chartId, objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
         ObjectSetInteger(m_chartId, objName, OBJPROP_COLOR, clrDimGray);
         ObjectSetInteger(m_chartId, objName, OBJPROP_BACK, false);
         ObjectSetInteger(m_chartId, objName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chartId, objName, OBJPROP_HIDDEN, true);
        }
     }

public:
   CWrDashboard(void)
     {
      m_chartId = 0;
      m_prefix  = WREA_DASH_PREFIX;
      m_x       = 15;
      m_y       = 25;
     }

   void Init(const long chartId,const string uniqueSuffix)
     {
      m_chartId = chartId;
      m_prefix  = WREA_DASH_PREFIX + uniqueSuffix + "_";
      CreateBackground(270, 210);
     }

   void Remove(void)
     {
      ObjectsDeleteAll(m_chartId, m_prefix);
      ChartRedraw(m_chartId);
     }

   void Update(const ENUM_WR_STATE state,const double equityPct,const double equity,const double balance,
               const int buyOpen,const bool buyPending,const int buyTierBoundary,
               const int sellOpen,const bool sellPending,const int sellTierBoundary,
               const int maxTierTotal)
     {
      color stateColor = clrLimeGreen;
      string stateText  = "OPERANDO";
      if(state == WR_STATE_PROFIT_TARGET_HIT) { stateColor = clrGold; stateText = "TRAVADO: META DE LUCRO"; }
      if(state == WR_STATE_PROTECTION_HIT)    { stateColor = clrRed;  stateText = "TRAVADO: PROTECAO DE EQUITY"; }
      if(state == WR_STATE_OUT_OF_SESSION)    { stateColor = clrSilver; stateText = "FORA DE SESSAO"; }

      color pctColor = (equityPct >= 0) ? clrLimeGreen : clrOrangeRed;

      int y = m_y;
      CreateLabel("Title", m_x, y, "Wick Reversal EA", clrWhite, 11); y += 22;
      CreateLabel("State", m_x, y, "Estado: " + stateText, stateColor); y += 20;
      CreateLabel("Eq", m_x, y, StringFormat("Equity vs referencia: %.2f%%", equityPct), pctColor); y += 18;
      CreateLabel("Bal", m_x, y, StringFormat("Equity: %.2f   Balance: %.2f", equity, balance), clrWhite); y += 22;

      CreateLabel("BuyHead", m_x, y, "COMPRA", clrDodgerBlue, 10); y += 18;
      CreateLabel("BuyLine", m_x, y, StringFormat("  Posicoes: %d/%d   Pendente: %s", buyOpen, maxTierTotal, (buyPending ? "sim" : "nao")), clrWhite); y += 22;

      CreateLabel("SellHead", m_x, y, "VENDA", clrTomato, 10); y += 18;
      CreateLabel("SellLine", m_x, y, StringFormat("  Posicoes: %d/%d   Pendente: %s", sellOpen, maxTierTotal, (sellPending ? "sim" : "nao")), clrWhite); y += 18;

      ChartRedraw(m_chartId);
     }
  };
