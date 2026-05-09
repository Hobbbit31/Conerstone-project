-- large_pipeline_4stage.vhd
-- 4-stage pipeline with 4 parallel data paths per stage.
-- Each stage has combinational logic feeding into a DFF register.
-- Structure: INPUT -> [Stage1 logic + DFF] -> [Stage2 logic + DFF] -> [Stage3 logic + DFF] -> [Stage4 logic + DFF] -> OUTPUT
-- 4 parallel paths means 4x the throughput opportunity.
-- Tests: DFF rising-edge capture, multi-level delta chains, inter-stage dependencies.
-- Layers: Stage1_comb(L0) -> Stage1_DFF(L1) -> Stage2_comb(L2) -> Stage2_DFF(L3) -> ...
-- Total: 16 DFFs + 16 combinational gates + clock + stimulus = deep dependency chain.

entity large_pipeline_4stage_tb is
end large_pipeline_4stage_tb;

architecture sim of large_pipeline_4stage_tb is

    -- clock
    signal CLK : std_logic := '0';

    -- 4 parallel input data signals
    signal D0, D1, D2, D3 : std_logic := '0';

    -- Stage 1 combinational (XOR with neighbour for mixing)
    signal S1_C0, S1_C1, S1_C2, S1_C3 : std_logic := '0';
    -- Stage 1 registered outputs
    signal S1_Q0, S1_Q0N : std_logic := '0';
    signal S1_Q1, S1_Q1N : std_logic := '0';
    signal S1_Q2, S1_Q2N : std_logic := '0';
    signal S1_Q3, S1_Q3N : std_logic := '0';

    -- Stage 2 combinational (NAND mixing)
    signal S2_C0, S2_C1, S2_C2, S2_C3 : std_logic := '0';
    -- Stage 2 registered outputs
    signal S2_Q0, S2_Q0N : std_logic := '0';
    signal S2_Q1, S2_Q1N : std_logic := '0';
    signal S2_Q2, S2_Q2N : std_logic := '0';
    signal S2_Q3, S2_Q3N : std_logic := '0';

    -- Stage 3 combinational (OR mixing)
    signal S3_C0, S3_C1, S3_C2, S3_C3 : std_logic := '0';
    -- Stage 3 registered outputs
    signal S3_Q0, S3_Q0N : std_logic := '0';
    signal S3_Q1, S3_Q1N : std_logic := '0';
    signal S3_Q2, S3_Q2N : std_logic := '0';
    signal S3_Q3, S3_Q3N : std_logic := '0';

    -- Stage 4 combinational (AND reduction)
    signal S4_C0, S4_C1, S4_C2, S4_C3 : std_logic := '0';
    -- Stage 4 registered outputs (final pipeline outputs)
    signal OUT0, OUT0N : std_logic := '0';
    signal OUT1, OUT1N : std_logic := '0';
    signal OUT2, OUT2N : std_logic := '0';
    signal OUT3, OUT3N : std_logic := '0';

begin

    -- Stage 1 combinational: XOR each input with its neighbour
    -- Layer 0 — depends only on inputs
    S1_C0 <= D0 xor D1;
    S1_C1 <= D1 xor D2;
    S1_C2 <= D2 xor D3;
    S1_C3 <= D3 xor D0;

    -- Stage 1 DFFs: register on rising clock edge
    -- Layer 1 — depends on S1_C* and CLK
    process(CLK) begin
        if rising_edge(CLK) then
            S1_Q0 <= S1_C0;
        end if;
    end process;

    process(CLK) begin
        if rising_edge(CLK) then
            S1_Q1 <= S1_C1;
        end if;
    end process;

    process(CLK) begin
        if rising_edge(CLK) then
            S1_Q2 <= S1_C2;
        end if;
    end process;

    process(CLK) begin
        if rising_edge(CLK) then
            S1_Q3 <= S1_C3;
        end if;
    end process;

    -- NOT outputs for stage 1 (Layer 1)
    S1_Q0N <= not S1_Q0;
    S1_Q1N <= not S1_Q1;
    S1_Q2N <= not S1_Q2;
    S1_Q3N <= not S1_Q3;

    -- Stage 2 combinational: NAND mixing of stage 1 outputs
    -- Layer 2 — depends on S1_Q*
    S2_C0 <= S1_Q0 nand S1_Q1;
    S2_C1 <= S1_Q1 nand S1_Q2;
    S2_C2 <= S1_Q2 nand S1_Q3;
    S2_C3 <= S1_Q3 nand S1_Q0;

    -- Stage 2 DFFs
    -- Layer 3 — depends on S2_C* and CLK
    process(CLK) begin
        if rising_edge(CLK) then
            S2_Q0 <= S2_C0;
        end if;
    end process;

    process(CLK) begin
        if rising_edge(CLK) then
            S2_Q1 <= S2_C1;
        end if;
    end process;

    process(CLK) begin
        if rising_edge(CLK) then
            S2_Q2 <= S2_C2;
        end if;
    end process;

    process(CLK) begin
        if rising_edge(CLK) then
            S2_Q3 <= S2_C3;
        end if;
    end process;

    -- NOT outputs for stage 2 (Layer 3)
    S2_Q0N <= not S2_Q0;
    S2_Q1N <= not S2_Q1;
    S2_Q2N <= not S2_Q2;
    S2_Q3N <= not S2_Q3;

    -- Stage 3 combinational: OR mixing of stage 2 outputs
    -- Layer 4 — depends on S2_Q*
    S3_C0 <= S2_Q0 or S2_Q1;
    S3_C1 <= S2_Q1 or S2_Q2;
    S3_C2 <= S2_Q2 or S2_Q3;
    S3_C3 <= S2_Q3 or S2_Q0;

    -- Stage 3 DFFs
    -- Layer 5 — depends on S3_C* and CLK
    process(CLK) begin
        if rising_edge(CLK) then
            S3_Q0 <= S3_C0;
        end if;
    end process;

    process(CLK) begin
        if rising_edge(CLK) then
            S3_Q1 <= S3_C1;
        end if;
    end process;

    process(CLK) begin
        if rising_edge(CLK) then
            S3_Q2 <= S3_C2;
        end if;
    end process;

    process(CLK) begin
        if rising_edge(CLK) then
            S3_Q3 <= S3_C3;
        end if;
    end process;

    -- NOT outputs for stage 3 (Layer 5)
    S3_Q0N <= not S3_Q0;
    S3_Q1N <= not S3_Q1;
    S3_Q2N <= not S3_Q2;
    S3_Q3N <= not S3_Q3;

    -- Stage 4 combinational: AND reduction of stage 3 outputs
    -- Layer 6 — depends on S3_Q*
    S4_C0 <= S3_Q0 and S3_Q1;
    S4_C1 <= S3_Q1 and S3_Q2;
    S4_C2 <= S3_Q2 and S3_Q3;
    S4_C3 <= S3_Q3 and S3_Q0;

    -- Stage 4 DFFs: final pipeline outputs
    -- Layer 7 — depends on S4_C* and CLK
    process(CLK) begin
        if rising_edge(CLK) then
            OUT0 <= S4_C0;
        end if;
    end process;

    process(CLK) begin
        if rising_edge(CLK) then
            OUT1 <= S4_C1;
        end if;
    end process;

    process(CLK) begin
        if rising_edge(CLK) then
            OUT2 <= S4_C2;
        end if;
    end process;

    process(CLK) begin
        if rising_edge(CLK) then
            OUT3 <= S4_C3;
        end if;
    end process;

    -- NOT outputs for stage 4 (Layer 7)
    OUT0N <= not OUT0;
    OUT1N <= not OUT1;
    OUT2N <= not OUT2;
    OUT3N <= not OUT3;

    -- Stimulus: drive inputs and clock through multiple cycles
    process begin
        -- t=0: all inputs low, clock low
        CLK <= '0';
        D0 <= '0'; D1 <= '0'; D2 <= '0'; D3 <= '0';
        wait for 5 ns;

        -- t=5: first clock edge
        CLK <= '1';
        wait for 5 ns;

        -- t=10: set D0=1, clock low
        CLK <= '0';
        D0 <= '1';
        wait for 5 ns;

        -- t=15: clock edge — S1 captures XOR(1,0)=1
        CLK <= '1';
        wait for 5 ns;

        -- t=20: set all inputs high, clock low
        CLK <= '0';
        D0 <= '1'; D1 <= '1'; D2 <= '1'; D3 <= '1';
        wait for 5 ns;

        -- t=25: clock edge — S1 captures XOR(1,1)=0 for all
        CLK <= '1';
        wait for 5 ns;

        -- t=30: alternating inputs, clock low
        CLK <= '0';
        D0 <= '1'; D1 <= '0'; D2 <= '1'; D3 <= '0';
        wait for 5 ns;

        -- t=35: clock edge
        CLK <= '1';
        wait for 5 ns;

        -- t=40: flip alternating, clock low
        CLK <= '0';
        D0 <= '0'; D1 <= '1'; D2 <= '0'; D3 <= '1';
        wait for 5 ns;

        -- t=45: clock edge — data propagates through stage 1
        CLK <= '1';
        wait for 5 ns;

        -- t=50: all low again, clock low
        CLK <= '0';
        D0 <= '0'; D1 <= '0'; D2 <= '0'; D3 <= '0';
        wait for 5 ns;

        -- t=55: clock edge — pipeline draining
        CLK <= '1';
        wait for 5 ns;

        -- t=60: clock low
        CLK <= '0';
        wait for 5 ns;

        -- t=65: clock edge
        CLK <= '1';
        wait for 5 ns;

        -- t=70: clock low
        CLK <= '0';
        wait for 5 ns;

        -- t=75: clock edge — data reaches stage 4 output
        CLK <= '1';
        wait for 5 ns;

        -- t=80: clock low
        CLK <= '0';
        wait for 5 ns;

        -- t=85: final clock edge
        CLK <= '1';
        wait for 5 ns;

        wait;
    end process;

end sim;
