-- ***************************************************************************
--                    Hexfront - Engine.Units
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

with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Ada.Containers.Vectors;
with Engine.Hexes;           use Engine.Hexes;
with Engine.Terrain;         use Engine.Terrain;

package Engine.Units is

   type Unit_Class is
     (Infantry, Cavalry, Armor, Recon, Artillery, Anti_Tank, Anti_Air,
      Engineer, Fortification, Fighter, Bomber, Warship);

   type Target_Kind is (Soft, Hard, Air);

   --  A unit type, as defined in an era data file.
   type Unit_Type is record
      Id          : Unbounded_String;
      Name        : Unbounded_String;
      Class       : Unit_Class  := Infantry;
      Mover       : Move_Class  := Foot;
      Target      : Target_Kind := Soft;
      Movement    : Natural     := 3;
      Max_Range   : Positive    := 1;
      Soft_Attack : Natural     := 5;
      Hard_Attack : Natural     := 1;
      Air_Attack  : Natural     := 0;
      Defense     : Natural     := 5;
      Spot        : Natural     := 2;     --  vision radius
      Buyable     : Boolean     := True;
      Max_Ammo    : Natural     := 8;
      Max_Fuel    : Natural     := 0;     --  0 = does not use fuel
      Cost        : Natural     := 100;
      --  Special abilities
      Charge          : Boolean := False; --  shock bonus when attacking
      Support         : Boolean := False; --  defensive support fire
      Ignore_Entrench : Boolean := False; --  e.g. pioneers / sappers
      Bombard         : Boolean := False; --  ranged attack suppresses
   end record;

   subtype Type_Index is Positive;
   package Type_Vectors is new Ada.Containers.Vectors (Type_Index, Unit_Type);

   Max_Strength   : constant := 10;
   Max_Experience : constant := 599;

   type Hex_Per_Side is array (Player_Side) of Hex;
   type Int_Per_Side is array (Player_Side) of Integer;

   type Unit is record
      Kind         : Type_Index  := 1;
      Side         : Player_Side := 1;
      Pos          : Hex         := No_Hex;
      Strength     : Natural     := Max_Strength;
      Ammo         : Natural     := 0;
      Fuel         : Natural     := 0;
      Experience   : Natural     := 0;
      Entrench     : Natural     := 0;
      Suppressed   : Natural     := 0;
      Moves_Left   : Natural     := 0;
      Has_Moved    : Boolean     := False;
      Has_Attacked : Boolean     := False;
      Alive        : Boolean     := True;
      Core         : Boolean     := False; --  campaign core unit
      Cut_Turns    : Natural     := 0;     --  turns spent out of supply
      --  What each side last saw of this unit (fog of war memory).
      Seen_Pos     : Hex_Per_Side := (others => No_Hex);
      Seen_Turn    : Int_Per_Side := (others => -100);
   end record;

   subtype Unit_Index is Positive;
   No_Unit : constant Natural := 0;
   package Unit_Vectors is new Ada.Containers.Vectors (Unit_Index, Unit);

   function Exp_Level (U : Unit) return Natural is
     (Natural'Min (U.Experience / 100, 5));

   function Is_Air (T : Unit_Type) return Boolean is (T.Mover = Air);
   function Is_Naval (T : Unit_Type) return Boolean is (T.Mover = Naval);

   --  The attack stat used against a given kind of target.
   function Attack_Stat (T : Unit_Type; K : Target_Kind) return Natural is
     (case K is
         when Soft => T.Soft_Attack,
         when Hard => T.Hard_Attack,
         when Air  => T.Air_Attack);

   function Class_Name (C : Unit_Class) return String;
end Engine.Units;
