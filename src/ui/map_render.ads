-- ***************************************************************************
--                     Hexfront - Map_Render
--
--           Copyright (C) 2026 By Ulrik Hørlyk Hjort
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
-- NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
-- LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
-- OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
-- WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- ***************************************************************************

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

   --  Draw units as silhouettes instead of map symbols.
   Silhouettes : Boolean := False;

   type View_State is record
      Selected    : Natural := 0;        --  selected unit
      Show_Reach  : Boolean := False;
      Reach       : Reach_Map;
      Hover       : Hex := No_Hex;
      Last_Fight  : Hex := No_Hex;       --  flash marker for last combat
      Viewer      : Engine.Side_Id := 0; --  whose fog to draw, 0 = none
      Deploy_Type : Natural := 0;        --  unit type being placed
      Show_Supply : Boolean := False;    --  shade hexes out of supply
   end record;

   function Center_X (H : Hex) return Gdouble;
   function Center_Y (H : Hex) return Gdouble;

   --  Size of the drawing area in screen pixels (zoom applied).
   procedure Map_Size (Width, Height : out Gint);

   --  Hex under screen pixel (X, Y), or No_Hex (zoom applied).
   function Hex_At (SX, SY : Gdouble) return Hex;

   procedure Draw (Cr : Cairo.Cairo_Context; V : View_State);

   --  Overview of the running game in a W x H area. Viewer selects the
   --  fog (0 = none); the rectangle VX, VY, VW, VH (unzoomed map pixels)
   --  marks the visible part of the map.
   procedure Draw_Minimap (Cr : Cairo.Cairo_Context; W, H : Gdouble;
                           Viewer : Engine.Side_Id;
                           VX, VY, VW, VH : Gdouble);

   --  Unzoomed map position under minimap pixel (MX, MY).
   procedure Minimap_To_Map (MX, MY, W, H : Gdouble; X, Y : out Gdouble);

   --  Unzoomed size of the whole map in pixels.
   function Map_Width return Gdouble;
   function Map_Height return Gdouble;

   --  Scaled-down overview of a scenario file (scenario chooser).
   procedure Draw_Preview (Cr : Cairo.Cairo_Context;
                           P  : Engine.Loader.Preview_Data;
                           W, H : Gdouble);

end Map_Render;
