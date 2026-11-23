-- ***************************************************************************
--                  Hexfront - Engine.Campaign
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

--  Campaigns: a chain of scenarios. Surviving core units carry their
--  experience (and the player's prestige) into the next battle.
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Ada.Containers.Vectors;
with Ada.Text_IO;
with Engine.Loader;
with Engine.Game;

package Engine.Campaign is

   type Carried_Unit is record
      Type_Id    : Unbounded_String;
      Experience : Natural := 0;
   end record;
   package Carried_Vectors is new Ada.Containers.Vectors
     (Positive, Carried_Unit);

   type Stage is record
      Id, File, On_Win, On_Loss : Unbounded_String;
      On_Decisive : Unbounded_String;   --  optional branch

   end record;
   package Stage_Vectors is new Ada.Containers.Vectors (Positive, Stage);

   type Campaign_State is record
      Active      : Boolean := False;
      Path        : Unbounded_String;
      Title       : Unbounded_String;
      Description : Unbounded_String;
      Player      : Player_Side := 1;
      Stages      : Stage_Vectors.Vector;
      Current     : Natural := 0;
      Prestige    : Integer := 0;    --  carried into the next stage
      Carried     : Carried_Vectors.Vector;
      Fresh       : Boolean := True; --  first stage: use scenario forces
      Won, Lost   : Natural := 0;
      Difficulty  : Engine.Game.Difficulty_Level := Engine.Game.Normal;
   end record;

   C : Campaign_State;

   Campaign_Error : exception;

   procedure Load_Campaign (Path : String);
   procedure Start_Stage;
   procedure Stop;

   --  Call when the current battle has a winner. Returns True if another
   --  stage follows (then call Start_Stage); Report describes the outcome.
   function Finish_Stage (Report : out Unbounded_String) return Boolean;

   function List_Campaigns return Engine.Loader.Info_Vectors.Vector;

   --  Between battles: core unit K (index into C.Carried) may be
   --  re-equipped with another type of the same class (e.g. light tank
   --  to medium tank), paid from the carried prestige. Experience stays.
   function Can_Upgrade (K : Positive; T : Positive) return Boolean;
   function Upgrade_Cost (K : Positive; T : Positive) return Natural;
   procedure Upgrade (K : Positive; T : Positive);

   --  Persistence (used by Engine.Save).
   procedure Write_State (F : Ada.Text_IO.File_Type);
   procedure Read_State_Line (Line : String);

   function Stage_Number return Natural is (C.Current);
   function Stage_Count return Natural is (Natural (C.Stages.Length));
end Engine.Campaign;
