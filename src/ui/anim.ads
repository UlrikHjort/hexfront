--  Plays the engine's effect queue (moves, combat, explosions ...) as
--  short animations with sound.
with Cairo;
with Glib;          use Glib;
with Engine;
with Engine.Units;
with Engine.Hexes;

package Anim is

   Enabled : Boolean := True;

   type Callback is access procedure;
   On_Redraw : Callback;   --  queue a redraw of the map
   On_Done   : Callback;   --  queue drained

   type Focus_Callback is access procedure (H : Engine.Hexes.Hex);
   On_Focus  : Focus_Callback;   --  bring a hex into view

   --  Take new effects from Engine.Game.Effects; Viewer filters out what
   --  the human player could not see (0 = show everything).
   procedure Enqueue (Viewer : Engine.Side_Id);
   procedure Clear;
   function Busy return Boolean;

   --  If unit U is currently sliding along a path, its centre position.
   function Override (U : Engine.Units.Unit_Index;
                      X, Y : out Gdouble) return Boolean;

   procedure Draw_Overlay (Cr : Cairo.Cairo_Context);

end Anim;
