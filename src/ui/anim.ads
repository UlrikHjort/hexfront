-- ***************************************************************************
--                        Hexfront - Anim
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
