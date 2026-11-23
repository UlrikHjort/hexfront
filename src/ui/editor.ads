-- ***************************************************************************
--                       Hexfront - Editor
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

--  The scenario editor: a floating tool window; the map in the main
--  window is the canvas.
with Glib;           use Glib;
with Gtk.Window;
with Engine.Hexes;

package Editor is

   type Callback is access procedure;
   type Path_Callback is access procedure (Path : String);

   On_Changed : Callback;       --  map content or size changed
   On_Test    : Path_Callback;  --  play-test the given scenario file
   On_Close   : Callback;       --  editor closed

   function Active return Boolean;

   procedure Open (Parent : Gtk.Window.Gtk_Window);

   procedure Click (H : Engine.Hexes.Hex; Button : Guint);
   procedure Drag (H : Engine.Hexes.Hex);   --  mouse moved, button held

   function Help_Text return String;        --  for the side panel

end Editor;
