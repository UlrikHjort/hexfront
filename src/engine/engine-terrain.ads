-- ***************************************************************************
--                   Hexfront - Engine.Terrain
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

package Engine.Terrain is
   pragma Pure;

   type Terrain_Kind is
     (Clear, Road, Forest, Hills, Mountain, River, Swamp,
      Town, City, Fortress, Water, Trench, Airfield);

   type Move_Class is (Foot, Horse, Wheeled, Tracked, Static, Air, Naval);

   Impassable : constant := 99;

   function Move_Cost (T : Terrain_Kind; M : Move_Class) return Natural;

   --  Added to the defence value of a unit standing in this terrain.
   function Defense_Bonus (T : Terrain_Kind) return Integer;

   --  Close terrain hampers vehicles and charging cavalry.
   function Is_Close (T : Terrain_Kind) return Boolean is
     (T in Forest | Mountain | Town | City | Fortress | Swamp);

   --  Terrain that can be owned and captured.
   function Is_Capturable (T : Terrain_Kind) return Boolean is
     (T in Town | City | Fortress | Airfield);

   procedure From_Char
     (C : Character; T : out Terrain_Kind; Ok : out Boolean);

   function Name (T : Terrain_Kind) return String;
end Engine.Terrain;
