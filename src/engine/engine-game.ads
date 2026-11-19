--  Game state and rules. The game is a singleton held in G.
--
--  Each hex has two layers: a ground slot and an air slot. Air units fly
--  over everything, ignore zones of control and need to return to an
--  airfield (or own town/city) for fuel.
with Ada.Strings.Unbounded;        use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with Ada.Containers.Vectors;
with Engine.Hexes;                 use Engine.Hexes;
with Engine.Terrain;               use Engine.Terrain;
with Engine.Units;                 use Engine.Units;

package Engine.Game is

   Max_Cols : constant := 60;
   Max_Rows : constant := 40;

   subtype Col_Range is Integer range 0 .. Max_Cols - 1;
   subtype Row_Range is Integer range 0 .. Max_Rows - 1;

   type Cell is record
      Terrain  : Terrain_Kind := Clear;
      Owner    : Side_Id      := 0;
      Victory  : Boolean      := False;
      Name     : Unbounded_String;
      Occupant : Natural      := No_Unit;   --  ground unit
      Air      : Natural      := No_Unit;   --  air unit
   end record;

   type Cell_Grid is array (Col_Range, Row_Range) of Cell;
   type Bool_Grid is array (Col_Range, Row_Range) of Boolean;
   type Vision_Array is array (Player_Side) of Bool_Grid;

   type Control_Kind is (Human, Computer);

   type RGB is record
      R, G, B : Float := 0.5;
   end record;

   type Side_Info is record
      Name     : Unbounded_String;
      Color    : RGB;
      Control  : Control_Kind := Human;
      Prestige : Integer      := 0;
      Income   : Integer      := 0;
      Buy_List : Unbounded_String;  --  ",id,id," ; empty = all buyable
   end record;

   type Side_Array is array (Player_Side) of Side_Info;

   --  Per-era rule tweaks.
   type Era_Rules is record
      Id           : Unbounded_String;
      Name         : Unbounded_String;
      Max_Entrench : Natural := 3;
      Charge_Bonus : Natural := 0;  --  attack bonus for Charge units
      Square_Bonus : Natural := 0;  --  infantry defence vs cavalry
      Close_Armor_Penalty : Natural := 3;
   end record;

   --  Tutorial / briefing hints, triggered by turn number or event.
   type Hint is record
      Turn  : Natural := 0;              --  0 = event triggered
      Event : Unbounded_String;
      Text  : Unbounded_String;
      Shown : Boolean := False;
   end record;
   package Hint_Vectors is new Ada.Containers.Vectors (Positive, Hint);

   --  Units scheduled to arrive at the start of a side's turn.
   type Reinforcement is record
      Turn : Positive    := 1;
      Side : Player_Side := 1;
      Kind : Positive    := 1;
      Pos  : Hex         := No_Hex;
      Core : Boolean     := False;
      Done : Boolean     := False;
   end record;
   package Reinf_Vectors is new Ada.Containers.Vectors
     (Positive, Reinforcement);

   type Difficulty_Level is (Easy, Normal, Hard);

   type Game_State is record
      Loaded        : Boolean := False;
      Scenario_Path : Unbounded_String;
      Title         : Unbounded_String;
      Description   : Unbounded_String;
      Category      : Unbounded_String;
      Era           : Era_Rules;
      Cols, Rows    : Natural := 0;
      Cells         : Cell_Grid;
      Seen          : Vision_Array := (others => (others => (others => True)));
      Fog           : Boolean := True;
      Fair_AI       : Boolean := True;   --  computer obeys fog of war
      Sides         : Side_Array;
      Types         : Type_Vectors.Vector;
      Units         : Unit_Vectors.Vector;
      Hints         : Hint_Vectors.Vector;
      Reinforcements : Reinf_Vectors.Vector;
      Difficulty    : Difficulty_Level := Normal;
      Victory_Grade : Unbounded_String;  --  e.g. "Decisive victory"
      Decisive      : Boolean := False;
      Turn          : Positive    := 1;
      Max_Turns     : Positive    := 10;
      First         : Player_Side := 1;
      Current       : Player_Side := 1;
      Attacker      : Player_Side := 1;
      Winner        : Side_Id     := 0;
   end record;

   G : Game_State;

   --------------
   -- Messages --
   --------------

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Positive, String);
   Messages      : String_Vectors.Vector;   --  combat log lines
   Pending_Hints : String_Vectors.Vector;   --  hint texts to pop up
   procedure Log (S : String);

   ----------------------------------------------
   -- Visual / audio effects for the front end --
   ----------------------------------------------

   type Fx_Kind is (Fx_Move, Fx_Combat, Fx_Destroyed, Fx_Capture, Fx_Deploy,
                    Fx_Victory);
   Max_Fx_Path : constant := 48;
   type Fx_Path is array (1 .. Max_Fx_Path) of Hex;

   type Fx_Event is record
      Kind     : Fx_Kind := Fx_Move;
      Unit     : Natural := 0;           --  mover / attacker / victim
      Path     : Fx_Path := (others => No_Hex);
      Len      : Natural := 0;
      From, To : Hex := No_Hex;          --  attacker and defender hexes
      A_Loss, D_Loss : Natural := 0;
      Kind_Of_Fire   : Unit_Class := Infantry;  --  attacker's class
      Air_Attack     : Boolean := False;        --  attacker is an aircraft
   end record;
   package Fx_Vectors is new Ada.Containers.Vectors (Positive, Fx_Event);
   Effects : Fx_Vectors.Vector;   --  drained by the GUI; cleared on Reset
   Record_Effects : Boolean := True;

   --  Signal a game event (select, move, attack, capture, kill, buy,
   --  ambush, ...). Queues any matching hint for a human player.
   procedure Raise_Event (Name : String);

   -------------
   -- Queries --
   -------------

   function In_Map (H : Hex) return Boolean is
     (H.Col in 0 .. G.Cols - 1 and then H.Row in 0 .. G.Rows - 1);

   function Terrain_At (H : Hex) return Terrain_Kind is
     (G.Cells (H.Col, H.Row).Terrain);

   function Unit_At (H : Hex) return Natural is
     (if In_Map (H) then G.Cells (H.Col, H.Row).Occupant else No_Unit);
   function Air_At (H : Hex) return Natural is
     (if In_Map (H) then G.Cells (H.Col, H.Row).Air else No_Unit);

   function Get (U : Unit_Index) return Unit is (G.Units (U));
   function Type_Of (U : Unit_Index) return Unit_Type is
     (G.Types (G.Units (U).Kind));
   function Is_Air (U : Unit_Index) return Boolean is
     (Is_Air (Type_Of (U)));
   function Unit_Name (U : Unit_Index) return String;
   function Find_Type (Id : String) return Natural;  --  0 if unknown

   function Is_Enemy (U : Natural; Side : Player_Side) return Boolean is
     (U /= No_Unit and then G.Units (U).Side /= Side);

   --  Enemy ground unit adjacent (zone of control), ignoring fog.
   function Enemy_Adjacent (H : Hex; Side : Player_Side) return Boolean;

   --  A ground unit with no escape hex: every neighbour is impassable,
   --  enemy held or inside an enemy zone of control. Surrounded units
   --  defend at -2 and cannot resupply or reinforce.
   function Is_Surrounded (U : Unit_Index) return Boolean;

   ------------
   -- Vision --
   ------------

   procedure Update_Vision;

   --  Can side By see unit U? (Human view, honours fog.)
   function Visible (U : Unit_Index; By : Player_Side) return Boolean;

   --  Does side By know about U right now? A computer player sees
   --  everything unless G.Fair_AI is set.
   function Known (U : Unit_Index; By : Player_Side) return Boolean;

   --  Known now, or seen within the last few turns (memory).
   function Remembered (U : Unit_Index; By : Player_Side) return Boolean;
   --  Where side By believes U to be.
   function Believed_Pos (U : Unit_Index; By : Player_Side) return Hex;

   function Hex_Seen (H : Hex; By : Player_Side) return Boolean is
     (not G.Fog or else G.Seen (By) (H.Col, H.Row));

   --------------
   -- Movement --
   --------------

   type Cost_Grid is array (Col_Range, Row_Range) of Integer;
   --  -1 = unreachable, otherwise movement points spent to get there

   type Reach_Map is record
      Cost   : Cost_Grid := (others => (others => -1));
      Parent : Cost_Grid := (others => (others => -1));  --  col*100+row
   end record;

   procedure Compute_Reach (U : Unit_Index; R : out Reach_Map);

   function Can_Move_To
     (U : Unit_Index; R : Reach_Map; H : Hex) return Boolean;

   --  Moves along the computed path. Hidden enemies may interrupt the
   --  move (ambush). Returns the hex actually reached.
   procedure Move_Unit (U : Unit_Index; To : Hex; R : Reach_Map);

   --  Human moves: like Move_Unit, but the move can be taken back if it
   --  revealed nothing (no new enemy seen, no capture, no ambush).
   procedure Move_Unit_Undoable (U : Unit_Index; To : Hex; R : Reach_Map);
   function Can_Undo return Boolean;
   procedure Undo_Move;

   ------------
   -- Combat --
   ------------

   function Can_Attack_From
     (A : Unit_Index; From : Hex; D : Unit_Index) return Boolean;

   function Can_Attack (A, D : Unit_Index) return Boolean is
     (Can_Attack_From (A, G.Units (A).Pos, D));

   --  The unit in hex H that A would attack (ground or air), or 0.
   function Target_In (A : Unit_Index; H : Hex) return Natural;

   type Prediction is record
      Att_Loss       : Float   := 0.0;
      Def_Loss       : Float   := 0.0;
      Support_Threat : Boolean := False;
   end record;

   function Predict
     (A : Unit_Index; From : Hex; D : Unit_Index) return Prediction;

   procedure Attack (A, D : Unit_Index);

   ----------------------
   -- Supply & reserve --
   ----------------------

   function On_Own_Base (U : Unit_Index) return Boolean;
   function Can_Resupply (U : Unit_Index) return Boolean;
   procedure Resupply (U : Unit_Index);

   function Reinforce_Cost (U : Unit_Index) return Natural;
   function Can_Reinforce (U : Unit_Index) return Boolean;
   procedure Reinforce (U : Unit_Index);

   --------------
   -- Purchase --
   --------------

   function May_Buy (T : Type_Index; Side : Player_Side) return Boolean;
   function Can_Deploy
     (T : Type_Index; Side : Player_Side; H : Hex) return Boolean;
   function Has_Deploy_Hex (T : Type_Index; Side : Player_Side)
                            return Boolean;
   procedure Buy (T : Type_Index; Side : Player_Side; H : Hex);

   ---------------
   -- Game flow --
   ---------------

   procedure Reset;
   procedure Add_Unit (U : Unit);
   procedure Remove_Unit (U : Unit_Index);   --  silently, e.g. campaign
   procedure Place_Occupants;                --  rebuild from unit list
   procedure Start_Game;

   --  Adjust prestige/experience for the chosen difficulty. Call once,
   --  after the human/computer sides are set.
   procedure Apply_Difficulty (D : Difficulty_Level);
   procedure End_Turn;
   procedure Check_Victory;

   function Victory_Hexes_Total return Natural;
   function Victory_Hexes_Owned (S : Player_Side) return Natural;

end Engine.Game;
