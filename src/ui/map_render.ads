--  Cairo rendering of the hex map and unit counters.
with Cairo;
with Glib;          use Glib;
with Engine;
with Engine.Hexes;  use Engine.Hexes;
with Engine.Game;   use Engine.Game;
with Engine.Loader;

package Map_Render is

   Radius : constant Gdouble := 30.0;   --  hex corner radius in pixels
   Margin : constant Gdouble := 8.0;

   --  Display zoom factor; all map geometry is in unzoomed units and the
   --  whole drawing is scaled by Cairo.
   Zoom     : Gdouble := 1.0;
   Min_Zoom : constant Gdouble := 0.45;
   Max_Zoom : constant Gdouble := 1.75;

   type View_State is record
      Selected    : Natural := 0;        --  selected unit
      Show_Reach  : Boolean := False;
      Reach       : Reach_Map;
      Hover       : Hex := No_Hex;
      Last_Fight  : Hex := No_Hex;       --  flash marker for last combat
      Viewer      : Engine.Side_Id := 0; --  whose fog to draw, 0 = none
      Deploy_Type : Natural := 0;        --  unit type being placed
   end record;

   function Center_X (H : Hex) return Gdouble;
   function Center_Y (H : Hex) return Gdouble;

   --  Size of the drawing area in screen pixels (zoom applied).
   procedure Map_Size (Width, Height : out Gint);

   --  Hex under screen pixel (X, Y), or No_Hex (zoom applied).
   function Hex_At (SX, SY : Gdouble) return Hex;

   procedure Draw (Cr : Cairo.Cairo_Context; V : View_State);

   --  Scaled-down overview of a scenario file (scenario chooser).
   procedure Draw_Preview (Cr : Cairo.Cairo_Context;
                           P  : Engine.Loader.Preview_Data;
                           W, H : Gdouble);

end Map_Render;
