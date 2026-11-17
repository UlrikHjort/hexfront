with Ada.Strings.Fixed;        use Ada.Strings.Fixed;
with Ada.Characters.Handling;  use Ada.Characters.Handling;

package body Engine.Text_Util is

   function Blank (C : Character) return Boolean is
     (C = ' ' or else C = ASCII.HT or else C = ASCII.CR);

   procedure Next_Token (Line : String; From : in out Natural;
                         First, Last : out Natural) is
   begin
      while From <= Line'Last and then Blank (Line (From)) loop
         From := From + 1;
      end loop;
      First := From;
      while From <= Line'Last and then not Blank (Line (From)) loop
         From := From + 1;
      end loop;
      Last := From - 1;
   end Next_Token;

   function Keyword (Line : String) return String is
      P : Natural := Line'First;
      F, L : Natural;
   begin
      Next_Token (Line, P, F, L);
      return To_Lower (Line (F .. L));
   end Keyword;

   function Rest (Line : String) return String is
      P : Natural := Line'First;
      F, L : Natural;
   begin
      Next_Token (Line, P, F, L);
      return Trim (Line (L + 1 .. Line'Last), Ada.Strings.Both);
   end Rest;

   function Value (Line, Key : String; Default : String := "")
                   return String is
      P : Natural := Line'First;
      F, L : Natural;
   begin
      Next_Token (Line, P, F, L);       --  skip keyword
      loop
         Next_Token (Line, P, F, L);
         exit when F > L;
         declare
            T : constant String := Line (F .. L);
            E : constant Natural := Index (T, "=");
         begin
            if E > 0 and then To_Lower (T (T'First .. E - 1)) = Key then
               return T (E + 1 .. T'Last);
            end if;
         end;
      end loop;
      return Default;
   end Value;

   function Int (Line, Key : String; Default : Integer := 0) return Integer
   is
      V : constant String := Value (Line, Key);
   begin
      return (if V = "" then Default else Integer'Value (V));
   exception
      when Constraint_Error =>
         return Default;
   end Int;

   function Has (Line, Key : String) return Boolean is
      P : Natural := Line'First;
      F, L : Natural;
   begin
      Next_Token (Line, P, F, L);
      loop
         Next_Token (Line, P, F, L);
         exit when F > L;
         declare
            T : constant String := To_Lower (Line (F .. L));
         begin
            if T = Key or else (T'Length > Key'Length
                                and then T (T'First .. T'First + Key'Length)
                                         = Key & "=")
            then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Has;

   function Image (N : Integer) return String is
      S : constant String := Integer'Image (N);
   begin
      return (if N < 0 then S else S (S'First + 1 .. S'Last));
   end Image;

end Engine.Text_Util;
