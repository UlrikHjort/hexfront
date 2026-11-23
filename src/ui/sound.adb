-- ***************************************************************************
--                       Hexfront - Sound
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

with Ada.Calendar;     use Ada.Calendar;
with Ada.Directories;
with GNAT.OS_Lib;      use GNAT.OS_Lib;
with Engine.Loader;

package body Sound is

   Player  : String_Access;
   Probed  : Boolean := False;
   Last    : Time := Clock;
   Last_Nm : String (1 .. 32) := (others => ' ');

   procedure Probe is
      Candidates : constant array (1 .. 3) of String_Access :=
        (new String'("/usr/bin/paplay"), new String'("/usr/bin/pw-play"),
         new String'("/usr/bin/aplay"));
   begin
      Probed := True;
      for C of Candidates loop
         if Is_Executable_File (C.all) then
            Player := C;
            return;
         end if;
      end loop;
   end Probe;

   procedure Play (Name : String) is
      File : constant String :=
        Ada.Directories.Full_Name (Engine.Loader.Data_Dir & "/sounds/"
                                   & Name & ".wav");
      Key  : String (1 .. 32) := (others => ' ');
   begin
      if not Enabled then
         return;
      end if;
      if not Probed then
         Probe;
      end if;
      if Player = null or else not Ada.Directories.Exists (File) then
         return;
      end if;
      --  Do not machine-gun the same sample.
      Key (1 .. Integer'Min (32, Name'Length)) :=
        Name (Name'First .. Name'First + Integer'Min (32, Name'Length) - 1);
      if Key = Last_Nm and then Clock - Last < 0.15 then
         return;
      end if;
      Last_Nm := Key;
      Last    := Clock;
      --  Background the player via the shell so we never wait for it
      --  and leave no zombie processes behind.
      declare
         Args : Argument_List :=
           (1 => new String'("-c"),
            2 => new String'("'" & Player.all & "' '" & File
                             & "' >/dev/null 2>&1 &"));
         Ok   : Boolean;
      begin
         Spawn ("/bin/sh", Args, Ok);
         for A of Args loop
            Free (A);
         end loop;
      end;
   exception
      when others =>
         null;   --  sound is never worth crashing over
   end Play;

end Sound;
