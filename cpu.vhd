-- cpu.vhd: Simple 8-bit CPU (BrainF*ck interpreter)
-- Copyright (C) 2020 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Matúš Vráblik
--

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.std_logic_arith.all;
    use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
    port (
        CLK   : in std_logic;  -- hodinovy signal
        RESET : in std_logic;  -- asynchronni reset procesoru
        EN    : in std_logic;  -- povoleni cinnosti procesoru

        -- synchronni pamet ROM
        CODE_ADDR : out std_logic_vector(11 downto 0); -- adresa do pameti
        CODE_DATA : in std_logic_vector(7 downto 0);   -- CODE_DATA <- rom[CODE_ADDR] pokud CODE_EN='1'
        CODE_EN   : out std_logic;                     -- povoleni cinnosti

        -- synchronni pamet RAM
        DATA_ADDR  : out std_logic_vector(9 downto 0); -- adresa do pameti
        DATA_WDATA : out std_logic_vector(7 downto 0); -- ram[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
        DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
        DATA_WE    : out std_logic;                    -- cteni (0) / zapis (1)
        DATA_EN    : out std_logic;                    -- povoleni cinnosti 

        -- vstupni port
        IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
        IN_VLD    : in std_logic;                      -- data platna
        IN_REQ    : out std_logic;                     -- pozadavek na vstup data

        -- vystupni port
        OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
        OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
        OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
    );
end cpu;

-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is
    -- PC --
    signal pc_reg: std_logic_vector(11 downto 0);
    signal pc_inc: std_logic;
    signal pc_dec: std_logic;
    signal pc_ld: std_logic;            
    -- PC --

    -- RAS --
    type r_array is array (15 downto 0) of std_logic_vector(11 downto 0);
    signal ras_reg: r_array:= (others => (others => '0'));
    signal ras_push: std_logic;
    signal ras_pop: std_logic;
    -- RAS --

    -- CNT --
    signal cnt_reg: std_logic_vector(3 downto 0):= "1111"; -- max 16 nested loops
    signal cnt_inc: std_logic;
    signal cnt_dec: std_logic;
    -- CNT --

    -- PTR --
    signal ptr_reg: std_logic_vector(9 downto 0);
    signal ptr_inc: std_logic;
    signal ptr_dec: std_logic;
    -- PTR --

    -- MUX --
    signal mx_select: std_logic_vector(1 downto 0);
    signal mx_output: std_logic_vector(7 downto 0);
    -- MUX --

    -- FSM STATES --
    type fsm_state is (
        s_start,
        s_fetch,
        s_decode,

        s_ptr_inc,
        s_ptr_dec,

        s_while_start,
        s_while_loop,
        s_while_end1,
        s_while_end2,

        s_value_inc,
        s_value_dec,

        s_write,
        s_read,

        s_null
    );
    signal state: fsm_state := s_start;
    signal pState,nstate: fsm_state;
    -- FSM STATES --

begin
    -- PC
    pc: process(CLK, RESET, pc_inc, pc_dec, pc_ld) is
    begin
        if RESET = '1' then
            pc_reg <= (others => '0');
        elsif rising_edge(CLK) then
            if pc_inc = '1' then
                pc_reg <= pc_reg + 1;
            elsif pc_dec = '1' then
                pc_reg <= pc_reg - 1;
            elsif pc_ld = '1' then
                pc_reg <= ras_reg(conv_integer(cnt_reg));
            end if;
        end if;
    end process;
    CODE_ADDR <= pc_reg;

    -- PTR
    ptr: process(CLK, RESET, ptr_inc, ptr_dec) is
    begin
        if RESET = '1' then
            ptr_reg <= (others => '0');
        elsif rising_edge(CLK) then
            if ptr_inc = '1' then 
                ptr_reg <= ptr_reg + 1;
            elsif ptr_dec = '1' then
                ptr_reg <= ptr_reg - 1;
            end if;
        end if;        
    end process;
    DATA_ADDR <= ptr_reg;

    -- CNT
    cnt: process(CLK, RESET, cnt_inc, cnt_dec) is
    begin
        if RESET = '1' then
            cnt_reg <= "1111";
        elsif rising_edge(CLK) then
            if cnt_inc = '1' then
                cnt_reg <= cnt_reg + 1;
            elsif cnt_dec = '1' then
                cnt_reg <= cnt_reg - 1;
            end if;     
        end if;
    end process;

    -- MUX
    mux: process(CLK, RESET, mx_select) is
    begin
        if RESET = '1' then
            mx_output <= (others => '0');
        elsif rising_edge(CLK) then
            case mx_select is
                when "01" =>
                    mx_output <= DATA_RDATA + 1;
                when "10" =>
                    mx_output <= DATA_RDATA - 1;
                when "00" =>
                    mx_output <= IN_DATA;
                when others =>
                    mx_output <= (others => '0');
            end case;
        end if;        
    end process;
    DATA_WDATA <= mx_output;

    --RAS
    ras: process(CLK, RESET, ras_push, ras_pop) is
    begin
        if RESET = '1' then
            ras_reg <= (others => (others => '0'));
        elsif rising_edge(CLK) then
            if ras_push = '1' then
                ras_reg(conv_integer(cnt_reg)) <= pc_reg;
            elsif ras_pop = '1' then
                ras_reg(conv_integer(cnt_reg)) <= (others => '0');
            end if;     
        end if;
    end process;

    -- FSM
    state_logic: process(CLK, RESET, EN) is
    begin
        if RESET = '1' then
            state <= s_start;
        elsif rising_edge(CLK) then
            if EN = '1' then
                state <= nState;
                pState <= state;
            end if;
        end if;        
    end process;

    fsm: process(state, OUT_BUSY, IN_VLD, CODE_DATA, DATA_RDATA) is
    begin
        -- initialization
        pc_inc <= '0';
        pc_dec <= '0';
        pc_ld <= '0';
        ras_pop <= '0';
        ras_push <= '0';
        ptr_inc <= '0';
        ptr_dec <= '0';
        cnt_inc <= '0';
        cnt_dec <= '0';

        CODE_EN <= '0';
        DATA_EN <= '0';
        DATA_WE <= '0';
        OUT_WE <= '0';

        mx_select <= "00";

        case state is
            when s_start =>
                nState <= s_fetch;
            when s_fetch =>
                CODE_EN <= '1';
                case pState is
                    when s_start =>
                        DATA_EN <= '1';
                    when s_ptr_inc =>
                        DATA_EN <= '1';
                    when s_ptr_dec =>
                        DATA_EN <= '1';
                    when s_value_inc => 
                        DATA_EN <= '1';
                        DATA_WE <= '1';
                    when s_value_dec => 
                        DATA_EN <= '1';
                        DATA_WE <= '1';
                    when s_while_end2 => 
                        DATA_EN <= '1';
                    when s_write =>
                        DATA_EN <= '1';
                    when s_read =>
                        DATA_EN <= '1';
                        DATA_WE <= '1';
                    when others =>
                        DATA_EN <= '0';
                end case;
                nState <= s_decode;
            when s_decode =>
                case CODE_DATA is
                    when x"3E" =>
                        nState <= s_ptr_inc;
                    when x"3C" =>
                        nState <= s_ptr_dec;
                    when x"2B" =>
                        nState <= s_value_inc;
                    when x"2D" =>
                        nState <= s_value_dec;
                    when x"5B" =>                        
                        nState <= s_while_start;
                        pc_inc <= '1';
                        DATA_EN <= '1';
                        cnt_inc <= '1';
                    when x"5D" =>
                        nState <= s_while_end1;
                        DATA_EN <= '1';
                    when x"2E" =>
                        nState <= s_write;
                    when x"2C" =>
                        nState <= s_read;
                    when x"00" =>
                        nState <= s_null;
                    when others =>
                        pc_inc <= '1';
                        nState <= s_fetch;
                end case;
            when s_ptr_inc =>
                ptr_inc <= '1';
                pc_inc <= '1';
                nState <= s_fetch;
            when s_ptr_dec =>
                ptr_dec <= '1';
                pc_inc <= '1';
                nState <= s_fetch;

            when s_value_inc => 
                pc_inc <= '1';   
                mx_select <= "01";
                nState <= s_fetch;
            when s_value_dec =>          
                pc_inc <= '1';
                mx_select <= "10";
                nState <= s_fetch;

            -- LOOP
            when s_while_start =>
                if DATA_RDATA /= x"00" then
                    ras_push <= '1';
                    nState <= s_fetch;
                else
                    DATA_EN <= '1';
                    CODE_EN <=  '1';
                    pc_inc <= '1';
                    nState <= s_while_loop;
                end if;
            when s_while_loop =>
                if CODE_DATA = x"5D" then
                    cnt_dec <= '1';
                    ras_pop <= '1';
                    nState <= s_fetch;
                else
                    pc_inc <= '1';
                    DATA_EN <= '1';
                    DATA_WE <= '0';
                    nState <= s_fetch;
                end if;
            when s_while_end1 =>
                DATA_EN <= '1';
                nState <= s_while_end2;
            when s_while_end2 =>
                if DATA_RDATA /= x"00" then
                    pc_ld <= '1';
                    nState <= s_fetch;
                else
                    pc_inc <= '1';
                    cnt_dec <= '1';
                    ras_pop <= '1';
                    nState <= s_fetch;
                end if;   
            -- LOOP    

            when s_write =>
                if OUT_BUSY = '1' then
                else
                    pc_inc <= '1';
                    OUT_DATA <= DATA_RDATA;
                    OUT_WE <= '1';
                    nState <= s_fetch;
                end if;
            when s_read =>
                if IN_VLD = '1' then
                    pc_inc <= '1';
                    nState <= s_fetch;
                else
                    IN_REQ <= '1';
                    mx_select <= "00";
                end if;   
            when s_null =>
        end case;    
    end process;



    -- zde dopiste vlastni VHDL kod


    -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
    --   - nelze z vice procesu ovladat stejny signal,
    --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
    --   - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
    --   - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly.

end behavioral;
