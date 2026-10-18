%% ================================================================
%  BATTERY-AWARE SMART DC FAST CHARGING STATION
%  VERSION 2.1 - STRESS-AWARE ADAPTIVE C-RATE CONTROL (UPDATED)
%
%  Battery: 48 V, 50 Ah Li-ion
%  Initial SOC: 20%
%  Target SOC: 95%
%
%  V2.1 improvements:
%  1. SOC-dependent base C-rate
%  2. Temperature-based derating
%  3. BSI-based derating
%  4. SOH-based derating
%  5. Current slew-rate limiting
%  6. Fixed 1C comparison (Validated CC-CV transition)
%  7. Controller response logging
%
%  NOTE:
%  This is a simplified behavioral battery model for algorithm
%  development and comparative charging-control analysis.
% ================================================================

clear;
clc;
close all;

fprintf('\n============================================================\n');
fprintf(' BATTERY-AWARE SMART DC FAST CHARGING STATION - V2.1\n');
fprintf('============================================================\n\n');

%% ================================================================
% 1. BATTERY AND SIMULATION PARAMETERS
% ================================================================

Q_nom = 50;                  % Battery capacity (Ah)
V_nom = 48;                  % Nominal battery voltage (V)

SOC_initial = 0.20;          % Initial SOC
SOC_target = 0.95;           % Target SOC

SOH_initial = 0.95;          % Initial SOH

T_initial = 25;              % Initial battery temperature (deg C)
Tamb = 25;                   % Ambient temperature (deg C)

R_initial = 0.050;           % Initial internal resistance (Ohm)

dt = 1;                      % Simulation time step (s)
t_end = 7200;                % Maximum simulation time (s)

V_min = 40;                  % Minimum battery voltage (V)
V_max = 54.6;                % Maximum charging voltage (V)

T_warning = 40;              % Temperature warning limit (deg C)
T_max = 45;                  % Maximum allowed temperature (deg C)

BSI_warning = 45;            % BSI warning threshold
BSI_high = 60;               % BSI high threshold
BSI_trip = 80;               % BSI emergency stop threshold

C_rate_max = 1.5;            % Maximum C-rate
Fixed_C_rate = 1.0;          % Fixed comparison C-rate

% Thermal model
Cth = 40000;                 % Thermal capacitance (J/deg C)
h = 20;                      % Heat transfer coefficient (W/deg C)

% SOH degradation coefficient
degradation_coeff = 2e-8;

%% ================================================================
% 2. OCV vs SOC LOOKUP TABLE
% ================================================================

SOC_table = [0 .1 .2 .3 .4 .5 .6 .7 .8 .9 1];

OCV_table = [40, 41.2, 42.8, 44.2, 45.3, ...
             46.2, 47.1, 48, 50.2, 52.8, 54.6];

%% ================================================================
% 3. RUN ADAPTIVE V2.1 SIMULATION
% ================================================================

fprintf('Running Adaptive V2.1 simulation...\n');

adaptive = runAdaptiveV21( ...
    Q_nom, V_nom, SOC_initial, SOC_target, ...
    SOH_initial, T_initial, Tamb, R_initial, ...
    dt, t_end, V_min, V_max, ...
    T_warning, T_max, ...
    BSI_warning, BSI_high, BSI_trip, ...
    C_rate_max, Cth, h, degradation_coeff, ...
    SOC_table, OCV_table);

%% ================================================================
% 4. RUN FIXED 1C SIMULATION
% ================================================================

fprintf('Running Fixed 1C simulation...\n');

fixed = runFixedV2( ...
    Q_nom, V_nom, SOC_initial, SOC_target, ...
    SOH_initial, T_initial, Tamb, R_initial, ...
    dt, t_end, V_min, V_max, ...
    T_warning, T_max, ...
    BSI_warning, BSI_high, BSI_trip, ...
    Fixed_C_rate, Cth, h, degradation_coeff, ...
    SOC_table, OCV_table);

%% ================================================================
% 5. DISPLAY FINAL RESULTS
% ================================================================

fprintf('\n============================================================\n');
fprintf(' ADAPTIVE V2.1 RESULTS\n');
fprintf('============================================================\n');

fprintf('Charging time        : %.2f minutes\n', adaptive.charge_time/60);
fprintf('Final SOC            : %.2f %%\n', adaptive.final_SOC*100);
fprintf('Final SOH            : %.4f %%\n', adaptive.final_SOH*100);
fprintf('Maximum temperature  : %.2f deg C\n', adaptive.max_temperature);
fprintf('Maximum BSI          : %.2f / 100\n', adaptive.max_BSI);
fprintf('Maximum current      : %.2f A\n', adaptive.max_current);
fprintf('Energy delivered     : %.4f kWh\n', adaptive.energy_kWh);

fprintf('\n============================================================\n');
fprintf(' FIXED 1C RESULTS\n');
fprintf('============================================================\n');

fprintf('Charging time        : %.2f minutes\n', fixed.charge_time/60);
fprintf('Final SOC            : %.2f %%\n', fixed.final_SOC*100);
fprintf('Final SOH            : %.4f %%\n', fixed.final_SOH*100);
fprintf('Maximum temperature  : %.2f deg C\n', fixed.max_temperature);
fprintf('Maximum BSI          : %.2f / 100\n', fixed.max_BSI);
fprintf('Maximum current      : %.2f A\n', fixed.max_current);
fprintf('Energy delivered     : %.4f kWh\n', fixed.energy_kWh);

%% ================================================================
% 6. PERFORMANCE COMPARISON
% ================================================================

speed_improvement = ...
    ((fixed.charge_time - adaptive.charge_time) ...
    / fixed.charge_time) * 100;

temperature_difference = ...
    fixed.max_temperature - adaptive.max_temperature;

bsi_difference = ...
    fixed.max_BSI - adaptive.max_BSI;

energy_difference = ...
    adaptive.energy_kWh - fixed.energy_kWh;

fprintf('\n============================================================\n');
fprintf(' PERFORMANCE COMPARISON\n');
fprintf('============================================================\n');

fprintf('Charging time improvement : %.2f %%\n', speed_improvement);
fprintf('Temperature difference    : %.2f deg C\n', temperature_difference);
fprintf('BSI difference            : %.2f\n', bsi_difference);
fprintf('Energy difference         : %.4f kWh\n', energy_difference);

fprintf('\n============================================================\n');
fprintf(' Adaptive V2.1 vs Fixed 1C\n');
fprintf('============================================================\n');

fprintf('%-25s %-15s %-15s\n', ...
    'Parameter', 'Adaptive V2.1', 'Fixed 1C');

fprintf('%-25s %-15.2f %-15.2f\n', ...
    'Charge time (min)', ...
    adaptive.charge_time/60, fixed.charge_time/60);

fprintf('%-25s %-15.2f %-15.2f\n', ...
    'Final SOC (%)', ...
    adaptive.final_SOC*100, fixed.final_SOC*100);

fprintf('%-25s %-15.4f %-15.4f\n', ...
    'Final SOH (%)', ...
    adaptive.final_SOH*100, fixed.final_SOH*100);

fprintf('%-25s %-15.2f %-15.2f\n', ...
    'Max Temperature (C)', ...
    adaptive.max_temperature, fixed.max_temperature);

fprintf('%-25s %-15.2f %-15.2f\n', ...
    'Max BSI', ...
    adaptive.max_BSI, fixed.max_BSI);

fprintf('%-25s %-15.2f %-15.2f\n', ...
    'Max Current (A)', ...
    adaptive.max_current, fixed.max_current);

fprintf('%-25s %-15.4f %-15.4f\n', ...
    'Energy (kWh)', ...
    adaptive.energy_kWh, fixed.energy_kWh);

%% ================================================================
% 7. GRAPH 1 - ADAPTIVE V2.1 MAIN PARAMETERS
% ================================================================

figure('Name','Adaptive V2.1 Main Parameters');

subplot(3,2,1);
plot(adaptive.time/60, adaptive.SOC*100, 'LineWidth', 1.5);
grid on;
xlabel('Time (min)');
ylabel('SOC (%)');
title('Adaptive V2.1 - SOC');

subplot(3,2,2);
plot(adaptive.time/60, adaptive.Voltage, 'LineWidth', 1.5);
grid on;
xlabel('Time (min)');
ylabel('Voltage (V)');
title('Battery Voltage');

subplot(3,2,3);
plot(adaptive.time/60, adaptive.Current, 'LineWidth', 1.5);
grid on;
xlabel('Time (min)');
ylabel('Current (A)');
title('Charging Current');

subplot(3,2,4);
plot(adaptive.time/60, adaptive.C_rate, 'LineWidth', 1.5);
grid on;
xlabel('Time (min)');
ylabel('C-rate');
title('Actual C-rate');

subplot(3,2,5);
plot(adaptive.time/60, adaptive.Temperature, 'LineWidth', 1.5);
grid on;
xlabel('Time (min)');
ylabel('Temperature (deg C)');
title('Battery Temperature');

subplot(3,2,6);
plot(adaptive.time/60, adaptive.BSI, 'LineWidth', 1.5);
grid on;
xlabel('Time (min)');
ylabel('BSI');
title('Battery Stress Index');

%% ================================================================
% 8. GRAPH 2 - SOH AND INTERNAL RESISTANCE
% ================================================================

figure('Name','Adaptive V2.1 SOH and Resistance');

subplot(2,1,1);
plot(adaptive.time/60, adaptive.SOH*100, 'LineWidth', 1.5);
grid on;
xlabel('Time (min)');
ylabel('SOH (%)');
title('Battery State of Health');

subplot(2,1,2);
plot(adaptive.time/60, adaptive.Rint, 'LineWidth', 1.5);
grid on;
xlabel('Time (min)');
ylabel('Resistance (Ohm)');
title('Internal Resistance');

%% ================================================================
% 9. GRAPH 3 - FIXED VS ADAPTIVE CURRENT
% ================================================================

figure('Name','Current Comparison');

plot(adaptive.time/60, adaptive.Current, 'LineWidth', 1.5);
hold on;
plot(fixed.time/60, fixed.Current, 'LineWidth', 1.5);
grid on;

xlabel('Time (min)');
ylabel('Current (A)');
title('Charging Current Comparison');

legend('Adaptive V2.1','Fixed 1C','Location','best');

%% ================================================================
% 10. GRAPH 4 - FIXED VS ADAPTIVE TEMPERATURE
% ================================================================

figure('Name','Temperature Comparison');

plot(adaptive.time/60, adaptive.Temperature, 'LineWidth', 1.5);
hold on;
plot(fixed.time/60, fixed.Temperature, 'LineWidth', 1.5);

yline(T_warning, '--', 'Warning');
yline(T_max, '--', 'Maximum');

grid on;

xlabel('Time (min)');
ylabel('Temperature (deg C)');
title('Battery Temperature Comparison');

legend('Adaptive V2.1','Fixed 1C','Warning','Maximum', ...
    'Location','best');

%% ================================================================
% 11. GRAPH 5 - FIXED VS ADAPTIVE BSI
% ================================================================

figure('Name','BSI Comparison');

plot(adaptive.time/60, adaptive.BSI, 'LineWidth', 1.5);
hold on;
plot(fixed.time/60, fixed.BSI, 'LineWidth', 1.5);

yline(BSI_warning, '--', 'Warning');
yline(BSI_high, '--', 'High');
yline(BSI_trip, '--', 'Trip');

grid on;

xlabel('Time (min)');
ylabel('Battery Stress Index');
title('Battery Stress Index Comparison');

legend('Adaptive V2.1','Fixed 1C', ...
    'Warning','High','Trip', ...
    'Location','best');

%% ================================================================
% 12. GRAPH 6 - CHARGING MODE
% ================================================================

figure('Name','Charging Mode');

stairs(adaptive.time/60, adaptive.ModeCode, 'LineWidth', 1.5);

grid on;

xlabel('Time (min)');
ylabel('Mode');
title('Adaptive V2.1 Charging Mode');

yticks([0 1 2]);
yticklabels({'STOP','CC','CV'});

%% ================================================================
% 13. GRAPH 7 - CONTROLLER RESPONSE
% ================================================================

figure('Name','Adaptive Controller Response');

subplot(3,1,1);

plot(adaptive.time/60, adaptive.Temperature, ...
    'LineWidth', 1.5);

grid on;

xlabel('Time (min)');
ylabel('Temperature (deg C)');
title('Temperature Response');

subplot(3,1,2);

plot(adaptive.time/60, adaptive.BSI, ...
    'LineWidth', 1.5);

grid on;

xlabel('Time (min)');
ylabel('BSI');
title('Battery Stress Index');

subplot(3,1,3);

plot(adaptive.time/60, adaptive.C_rate, ...
    'LineWidth', 1.5);

hold on;

plot(adaptive.time/60, adaptive.Commanded_C_rate, ...
    '--', 'LineWidth', 1.5);

grid on;

xlabel('Time (min)');
ylabel('C-rate');

title('Actual vs Commanded C-rate');

legend('Actual C-rate','Commanded C-rate', ...
    'Location','best');

%% ================================================================
% 14. GRAPH 8 - TEMPERATURE AND BSI DERATING FACTORS
% ================================================================

figure('Name','Controller Derating Factors');

subplot(2,1,1);

plot(adaptive.time/60, adaptive.TempFactor, ...
    'LineWidth', 1.5);

grid on;

xlabel('Time (min)');
ylabel('Temperature Factor');
title('Temperature Derating Factor');

ylim([0 1.1]);

subplot(2,1,2);

plot(adaptive.time/60, adaptive.BSIFactor, ...
    'LineWidth', 1.5);

grid on;

xlabel('Time (min)');
ylabel('BSI Factor');
title('BSI Derating Factor');

ylim([0 1.1]);

%% ================================================================
% 15. EXPORT ADAPTIVE DATA TO CSV
% ================================================================

adaptive_table = table( ...
    adaptive.time', ...
    adaptive.SOC', ...
    adaptive.Voltage', ...
    adaptive.Current', ...
    adaptive.Power', ...
    adaptive.Temperature', ...
    adaptive.SOH', ...
    adaptive.Rint', ...
    adaptive.C_rate', ...
    adaptive.Commanded_C_rate', ...
    adaptive.TempFactor', ...
    adaptive.BSIFactor', ...
    adaptive.BSI', ...
    adaptive.ModeCode', ...
    adaptive.Mode', ...
    'VariableNames', { ...
    'Time_s', ...
    'SOC', ...
    'Voltage_V', ...
    'Current_A', ...
    'Power_W', ...
    'Temperature_C', ...
    'SOH', ...
    'Rint_Ohm', ...
    'Actual_C_rate', ...
    'Commanded_C_rate', ...
    'Temperature_Factor', ...
    'BSI_Factor', ...
    'BSI', ...
    'ModeCode', ...
    'Mode'});

writetable(adaptive_table, ...
    'adaptive_V21_simulation_data.csv');

%% ================================================================
% 16. EXPORT FIXED DATA TO CSV
% ================================================================

fixed_table = table( ...
    fixed.time', ...
    fixed.SOC', ...
    fixed.Voltage', ...
    fixed.Current', ...
    fixed.Power', ...
    fixed.Temperature', ...
    fixed.SOH', ...
    fixed.Rint', ...
    fixed.C_rate', ...
    fixed.BSI', ...
    fixed.ModeCode', ...
    fixed.Mode', ...
    'VariableNames', { ...
    'Time_s', ...
    'SOC', ...
    'Voltage_V', ...
    'Current_A', ...
    'Power_W', ...
    'Temperature_C', ...
    'SOH', ...
    'Rint_Ohm', ...
    'C_rate', ...
    'BSI', ...
    'ModeCode', ...
    'Mode'});

writetable(fixed_table, ...
    'fixed_V1C_simulation_data.csv');

fprintf('\nCSV files successfully created.\n');

fprintf('\n============================================================\n');
fprintf(' SIMULATION COMPLETE\n');
fprintf('============================================================\n');

%% ================================================================
% FUNCTION 1 - ADAPTIVE V2.1 SIMULATION
% ================================================================

function result = runAdaptiveV21( ...
    Q_nom, V_nom, SOC_initial, SOC_target, ...
    SOH_initial, T_initial, Tamb, R_initial, ...
    dt, t_end, V_min, V_max, ...
    T_warning, T_max, ...
    BSI_warning, BSI_high, BSI_trip, ...
    C_rate_max, Cth, h, degradation_coeff, ...
    SOC_table, OCV_table)

    N = floor(t_end/dt) + 1;

    time = zeros(1,N);
    SOC = zeros(1,N);
    Voltage = zeros(1,N);
    Current = zeros(1,N);
    Power = zeros(1,N);
    Temperature = zeros(1,N);
    SOH = zeros(1,N);
    Rint = zeros(1,N);
    C_rate = zeros(1,N);
    BSI = zeros(1,N);

    ModeCode = zeros(1,N);

    TempFactor = ones(1,N);
    BSIFactor = ones(1,N);

    Commanded_C_rate = zeros(1,N);

    Mode = strings(1,N);

    SOC(1) = SOC_initial;
    SOH(1) = SOH_initial;
    Temperature(1) = T_initial;

    Rint(1) = estimateResistance( ...
        SOC(1), SOH(1), Temperature(1), R_initial);

    OCV = interp1( ...
        SOC_table, OCV_table, SOC(1), 'pchip');

    Voltage(1) = OCV;

    Mode(1) = "STOP";

    energy_J = 0;

    stopIndex = N;

    %% Maximum current slew rate
    max_current_change = 5;       % A/s

    for k = 1:N-1

        time(k) = (k-1)*dt;

        %% --------------------------------------------------------
        % Calculate internal resistance
        % ---------------------------------------------------------

        Rint(k) = estimateResistance( ...
            SOC(k), SOH(k), Temperature(k), R_initial);

        %% --------------------------------------------------------
        % Calculate OCV
        % ---------------------------------------------------------

        OCV = interp1( ...
            SOC_table, OCV_table, SOC(k), 'pchip');

        %% --------------------------------------------------------
        % Calculate BSI before controller
        % ---------------------------------------------------------

        if k == 1
            previous_current = 0;
        else
            previous_current = Current(k-1);
        end

        BSI_pre = calculateBSI( ...
            SOC(k), Temperature(k), SOH(k), ...
            Rint(k), previous_current, ...
            Q_nom, C_rate_max, ...
            T_max, R_initial);

        %% --------------------------------------------------------
        % Adaptive controller
        % ---------------------------------------------------------

        [C_target, tempFactor, bsiFactor] = adaptiveController( ...
            SOC(k), Temperature(k), SOH(k), ...
            BSI_pre, OCV, Rint(k), ...
            SOC_target, ...
            T_warning, T_max, ...
            BSI_warning, BSI_high, BSI_trip, ...
            V_max, C_rate_max);

        %% Store controller information

        TempFactor(k) = tempFactor;
        BSIFactor(k) = bsiFactor;
        Commanded_C_rate(k) = C_target;

        %% --------------------------------------------------------
        % Convert C-rate to current
        % ---------------------------------------------------------

        I_CC = C_target * Q_nom;

        %% --------------------------------------------------------
        % Current slew-rate limiter
        % ---------------------------------------------------------

        if k > 1

            previous_current = Current(k-1);

            if I_CC > previous_current + max_current_change

                I_CC = previous_current + max_current_change;

            elseif I_CC < previous_current - max_current_change

                I_CC = previous_current - max_current_change;

            end

        end

        I_CC = max(I_CC,0);

        %% --------------------------------------------------------
        % Constant-voltage current limit
        % ---------------------------------------------------------

        I_CV = (V_max - OCV) / Rint(k);

        I_CV = max(I_CV,0);

        %% --------------------------------------------------------
        % Actual current
        % ---------------------------------------------------------

        Current(k) = min(I_CC,I_CV);

        Current(k) = max(Current(k),0);

        %% --------------------------------------------------------
        % Charging mode
        % ---------------------------------------------------------

        if Current(k) <= 0

            ModeCode(k) = 0;
            Mode(k) = "STOP";

        elseif I_CV < I_CC

            ModeCode(k) = 2;
            Mode(k) = "CV";

        else

            ModeCode(k) = 1;
            Mode(k) = "CC";

        end

        %% --------------------------------------------------------
        % Actual C-rate
        % ---------------------------------------------------------

        C_rate(k) = Current(k)/Q_nom;

        %% --------------------------------------------------------
        % Battery terminal voltage
        % ---------------------------------------------------------

        Voltage(k) = OCV + Current(k)*Rint(k);

        %% --------------------------------------------------------
        % Over-voltage safety protection (Hardware Fault Trip)
        % ---------------------------------------------------------

        if Voltage(k) > V_max + 0.05

            Voltage(k) = V_max;
            Current(k) = 0;
            C_rate(k) = 0;

            ModeCode(k) = 0;
            Mode(k) = "STOP";

        else

            Voltage(k) = min(Voltage(k), V_max);

        end

        %% --------------------------------------------------------
        % Thermal model
        %
        % Cth*dT/dt = I^2*R - h*(T-Tamb)
        % ---------------------------------------------------------

        heat_generation = ...
            Current(k)^2 * Rint(k);

        heat_loss = ...
            h * (Temperature(k) - Tamb);

        dTdt = ...
            (heat_generation - heat_loss)/Cth;

        Temperature(k+1) = ...
            Temperature(k) + dTdt*dt;

        Temperature(k+1) = ...
            max(Temperature(k+1),Tamb);

        %% --------------------------------------------------------
        % SOC update
        % ---------------------------------------------------------

        dSOC = ...
            Current(k)*dt/(Q_nom*3600);

        SOC(k+1) = ...
            SOC(k) + dSOC;

        SOC(k+1) = ...
            min(SOC(k+1),1);

        %% --------------------------------------------------------
        % SOH degradation
        % ---------------------------------------------------------

        temperature_factor = ...
            1 + 0.05*max(Temperature(k)-25,0);

        C_rate_factor = ...
            1 + 0.5*C_rate(k)^2;

        degradation = ...
            degradation_coeff * ...
            C_rate_factor * ...
            temperature_factor * dt;

        SOH(k+1) = ...
            SOH(k) - degradation;

        SOH(k+1) = ...
            max(SOH(k+1),0);

        %% --------------------------------------------------------
        % Calculate BSI using actual charging conditions
        % ---------------------------------------------------------

        BSI(k) = calculateBSI( ...
            SOC(k), Temperature(k), SOH(k), ...
            Rint(k), Current(k), ...
            Q_nom, C_rate_max, ...
            T_max, R_initial);

        %% --------------------------------------------------------
        % Power
        % ---------------------------------------------------------

        Power(k) = ...
            Voltage(k)*Current(k);

        %% --------------------------------------------------------
        % Energy
        % ---------------------------------------------------------

        energy_J = ...
            energy_J + Power(k)*dt;

        %% --------------------------------------------------------
        % Stop if target SOC reached
        % ---------------------------------------------------------

        if SOC(k+1) >= SOC_target

            SOC(k+1) = SOC_target;

            stopIndex = k+1;

            Rint(k+1) = estimateResistance( ...
                SOC(k+1), SOH(k+1), ...
                Temperature(k+1), R_initial);

            Voltage(k+1) = interp1( ...
                SOC_table, OCV_table, ...
                SOC(k+1), 'pchip');

            Current(k+1) = 0;
            C_rate(k+1) = 0;

            BSI(k+1) = 0;

            ModeCode(k+1) = 0;
            Mode(k+1) = "STOP";

            break;

        end

        %% --------------------------------------------------------
        % Emergency temperature stop
        % ---------------------------------------------------------

        if Temperature(k+1) >= T_max

            stopIndex = k+1;

            Current(k+1) = 0;
            C_rate(k+1) = 0;

            BSI(k+1) = calculateBSI( ...
                SOC(k+1), Temperature(k+1), ...
                SOH(k+1), Rint(k), 0, ...
                Q_nom, C_rate_max, ...
                T_max, R_initial);

            ModeCode(k+1) = 0;
            Mode(k+1) = "STOP";

            break;

        end

        %% --------------------------------------------------------
        % Emergency BSI stop
        % ---------------------------------------------------------

        if BSI(k) >= BSI_trip

            stopIndex = k;

            Current(k) = 0;
            C_rate(k) = 0;

            ModeCode(k) = 0;
            Mode(k) = "STOP";

            break;

        end

    end

    %% ------------------------------------------------------------
    % Handle normal simulation completion
    % ------------------------------------------------------------

    if stopIndex == N

        stopIndex = N;

    end

    %% ------------------------------------------------------------
    % Fill final time
    % ------------------------------------------------------------

    time(stopIndex) = (stopIndex-1)*dt;

    %% ------------------------------------------------------------
    % Trim arrays
    % ------------------------------------------------------------

    time = time(1:stopIndex);
    SOC = SOC(1:stopIndex);
    Voltage = Voltage(1:stopIndex);
    Current = Current(1:stopIndex);
    Power = Power(1:stopIndex);
    Temperature = Temperature(1:stopIndex);
    SOH = SOH(1:stopIndex);
    Rint = Rint(1:stopIndex);
    C_rate = C_rate(1:stopIndex);
    BSI = BSI(1:stopIndex);
    ModeCode = ModeCode(1:stopIndex);
    Mode = Mode(1:stopIndex);

    TempFactor = TempFactor(1:stopIndex);
    BSIFactor = BSIFactor(1:stopIndex);
    Commanded_C_rate = Commanded_C_rate(1:stopIndex);

    %% ------------------------------------------------------------
    % Final calculations
    % ------------------------------------------------------------

    final_SOC = SOC(end);
    final_SOH = SOH(end);

    max_temperature = max(Temperature);
    max_BSI = max(BSI);
    max_current = max(Current);

    energy_kWh = energy_J/3.6e6;

    targetIndex = find(SOC >= SOC_target,1,'first');

    if ~isempty(targetIndex)

        charge_time = time(targetIndex);

    else

        charge_time = time(end);

    end

    %% ------------------------------------------------------------
    % Return results
    % ------------------------------------------------------------

    result.time = time;
    result.SOC = SOC;
    result.Voltage = Voltage;
    result.Current = Current;
    result.Power = Power;
    result.Temperature = Temperature;
    result.SOH = SOH;
    result.Rint = Rint;
    result.C_rate = C_rate;
    result.BSI = BSI;

    result.ModeCode = ModeCode;
    result.Mode = Mode;

    result.Commanded_C_rate = Commanded_C_rate;
    result.TempFactor = TempFactor;
    result.BSIFactor = BSIFactor;

    result.final_SOC = final_SOC;
    result.final_SOH = final_SOH;

    result.max_temperature = max_temperature;
    result.max_BSI = max_BSI;
    result.max_current = max_current;

    result.energy_kWh = energy_kWh;
    result.charge_time = charge_time;

end

%% ================================================================
% FUNCTION 2 - FIXED 1C SIMULATION
% ================================================================

function result = runFixedV2( ...
    Q_nom, V_nom, SOC_initial, SOC_target, ...
    SOH_initial, T_initial, Tamb, R_initial, ...
    dt, t_end, V_min, V_max, ...
    T_warning, T_max, ...
    BSI_warning, BSI_high, BSI_trip, ...
    Fixed_C_rate, Cth, h, degradation_coeff, ...
    SOC_table, OCV_table)

    N = floor(t_end/dt) + 1;

    time = zeros(1,N);
    SOC = zeros(1,N);
    Voltage = zeros(1,N);
    Current = zeros(1,N);
    Power = zeros(1,N);
    Temperature = zeros(1,N);
    SOH = zeros(1,N);
    Rint = zeros(1,N);
    C_rate = zeros(1,N);
    BSI = zeros(1,N);

    ModeCode = zeros(1,N);
    Mode = strings(1,N);

    SOC(1) = SOC_initial;
    SOH(1) = SOH_initial;
    Temperature(1) = T_initial;

    Rint(1) = estimateResistance( ...
        SOC(1), SOH(1), Temperature(1), R_initial);

    OCV = interp1( ...
        SOC_table, OCV_table, SOC(1), 'pchip');

    Voltage(1) = OCV;

    Mode(1) = "STOP";

    energy_J = 0;

    stopIndex = N;

    for k = 1:N-1

        time(k) = (k-1)*dt;

        %% Internal resistance

        Rint(k) = estimateResistance( ...
            SOC(k), SOH(k), Temperature(k), R_initial);

        %% OCV

        OCV = interp1( ...
            SOC_table, OCV_table, SOC(k), 'pchip');

        %% Fixed CC current

        I_CC = Fixed_C_rate * Q_nom;

        %% CV current limit

        I_CV = (V_max - OCV)/Rint(k);

        I_CV = max(I_CV,0);

        %% Actual current

        Current(k) = min(I_CC,I_CV);

        Current(k) = max(Current(k),0);

        %% Charging mode

        if Current(k) <= 0

            ModeCode(k) = 0;
            Mode(k) = "STOP";

        elseif I_CV < I_CC

            ModeCode(k) = 2;
            Mode(k) = "CV";

        else

            ModeCode(k) = 1;
            Mode(k) = "CC";

        end

        %% C-rate

        C_rate(k) = Current(k)/Q_nom;

        %% Terminal voltage

        Voltage(k) = OCV + Current(k)*Rint(k);

        %% Over-voltage safety protection (Hardware Fault Trip)

        if Voltage(k) > V_max + 0.05

            Voltage(k) = V_max;
            Current(k) = 0;
            C_rate(k) = 0;

            ModeCode(k) = 0;
            Mode(k) = "STOP";

        else

            Voltage(k) = min(Voltage(k), V_max);

        end

        %% Thermal model

        heat_generation = ...
            Current(k)^2 * Rint(k);

        heat_loss = ...
            h * (Temperature(k) - Tamb);

        dTdt = ...
            (heat_generation - heat_loss)/Cth;

        Temperature(k+1) = ...
            Temperature(k) + dTdt*dt;

        Temperature(k+1) = ...
            max(Temperature(k+1),Tamb);

        %% SOC update

        dSOC = ...
            Current(k)*dt/(Q_nom*3600);

        SOC(k+1) = ...
            SOC(k) + dSOC;

        SOC(k+1) = ...
            min(SOC(k+1),1);

        %% SOH degradation

        temperature_factor = ...
            1 + 0.05*max(Temperature(k)-25,0);

        C_rate_factor = ...
            1 + 0.5*C_rate(k)^2;

        degradation = ...
            degradation_coeff * ...
            C_rate_factor * ...
            temperature_factor * dt;

        SOH(k+1) = ...
            SOH(k) - degradation;

        SOH(k+1) = ...
            max(SOH(k+1),0);

        %% BSI

        BSI(k) = calculateBSI( ...
            SOC(k), Temperature(k), SOH(k), ...
            Rint(k), Current(k), ...
            Q_nom, Fixed_C_rate, ...
            T_max, R_initial);

        %% Power

        Power(k) = ...
            Voltage(k)*Current(k);

        %% Energy

        energy_J = ...
            energy_J + Power(k)*dt;

        %% Target reached

        if SOC(k+1) >= SOC_target

            SOC(k+1) = SOC_target;

            stopIndex = k+1;

            Rint(k+1) = estimateResistance( ...
                SOC(k+1), SOH(k+1), ...
                Temperature(k+1), R_initial);

            Voltage(k+1) = interp1( ...
                SOC_table, OCV_table, ...
                SOC(k+1), 'pchip');

            Current(k+1) = 0;
            C_rate(k+1) = 0;

            BSI(k+1) = 0;

            ModeCode(k+1) = 0;
            Mode(k+1) = "STOP";

            break;

        end

        %% Temperature emergency stop

        if Temperature(k+1) >= T_max

            stopIndex = k+1;

            Current(k+1) = 0;
            C_rate(k+1) = 0;

            ModeCode(k+1) = 0;
            Mode(k+1) = "STOP";

            break;

        end

        %% BSI emergency stop

        if BSI(k) >= BSI_trip

            stopIndex = k;

            Current(k) = 0;
            C_rate(k) = 0;

            ModeCode(k) = 0;
            Mode(k) = "STOP";

            break;

        end

    end

    %% Final time

    time(stopIndex) = (stopIndex-1)*dt;

    %% Trim arrays

    time = time(1:stopIndex);
    SOC = SOC(1:stopIndex);
    Voltage = Voltage(1:stopIndex);
    Current = Current(1:stopIndex);
    Power = Power(1:stopIndex);
    Temperature = Temperature(1:stopIndex);
    SOH = SOH(1:stopIndex);
    Rint = Rint(1:stopIndex);
    C_rate = C_rate(1:stopIndex);
    BSI = BSI(1:stopIndex);
    ModeCode = ModeCode(1:stopIndex);
    Mode = Mode(1:stopIndex);

    %% Final calculations

    final_SOC = SOC(end);
    final_SOH = SOH(end);

    max_temperature = max(Temperature);
    max_BSI = max(BSI);
    max_current = max(Current);

    energy_kWh = energy_J/3.6e6;

    targetIndex = find(SOC >= SOC_target,1,'first');

    if ~isempty(targetIndex)

        charge_time = time(targetIndex);

    else

        charge_time = time(end);

    end

    %% Return results

    result.time = time;
    result.SOC = SOC;
    result.Voltage = Voltage;
    result.Current = Current;
    result.Power = Power;
    result.Temperature = Temperature;
    result.SOH = SOH;
    result.Rint = Rint;
    result.C_rate = C_rate;
    result.BSI = BSI;

    result.ModeCode = ModeCode;
    result.Mode = Mode;

    result.final_SOC = final_SOC;
    result.final_SOH = final_SOH;

    result.max_temperature = max_temperature;
    result.max_BSI = max_BSI;
    result.max_current = max_current;

    result.energy_kWh = energy_kWh;
    result.charge_time = charge_time;

end

%% ================================================================
% FUNCTION 3 - INTERNAL RESISTANCE MODEL
% ================================================================

function R = estimateResistance( ...
    SOC, SOH, Temperature, R_initial)

    %% SOC effect

    soc_normalized = ...
        abs(SOC - 0.5)/0.5;

    soc_factor = ...
        1 + 0.30*(soc_normalized^1.2);

    %% SOH effect

    soh_factor = ...
        1 + 1.2*max(0,1-SOH);

    %% Temperature effect

    temp_factor = ...
        exp(-0.015*(Temperature-25));

    temp_factor = ...
        min(max(temp_factor,0.75),1.25);

    %% Final resistance

    R = ...
        R_initial * ...
        soc_factor * ...
        soh_factor * ...
        temp_factor;

end

%% ================================================================
% FUNCTION 4 - BATTERY STRESS INDEX
% ================================================================

function BSI = calculateBSI( ...
    SOC, Temperature, SOH, Rint, Current, ...
    Q_nom, C_rate_max, T_max, R_initial)

    %% C-rate stress

    actual_C_rate = ...
        abs(Current)/Q_nom;

    stress_C = ...
        min(actual_C_rate/C_rate_max,1);

    %% Temperature stress

    stress_T = ...
        (Temperature-25)/(T_max-25);

    stress_T = ...
        min(max(stress_T,0),1);

    %% SOC stress

    if SOC < 0.50

        stress_SOC = 0.10;

    elseif SOC < 0.70

        stress_SOC = 0.30;

    elseif SOC < 0.85

        stress_SOC = 0.55;

    elseif SOC < 0.95

        stress_SOC = 0.85;

    else

        stress_SOC = 1.00;

    end

    %% Resistance stress

    stress_R = ...
        (Rint/R_initial - 1)/0.50;

    stress_R = ...
        min(max(stress_R,0),1);

    %% SOH stress

    stress_SOH = ...
        (1-SOH)/0.30;

    stress_SOH = ...
        min(max(stress_SOH,0),1);

    %% Weights

    wC = 0.35;
    wT = 0.25;
    wSOC = 0.20;
    wR = 0.10;
    wSOH = 0.10;

    %% Battery Stress Index

    BSI = 100 * ( ...
        wC*stress_C + ...
        wT*stress_T + ...
        wSOC*stress_SOC + ...
        wR*stress_R + ...
        wSOH*stress_SOH);

    BSI = ...
        min(max(BSI,0),100);

end

%% ================================================================
% FUNCTION 5 - ADAPTIVE V2.1 CONTROLLER
% ================================================================

function [C_target, tempFactor, bsiFactor] = adaptiveController( ...
    SOC, Temperature, SOH, BSI, OCV, Rint, SOC_target, ...
    T_warning, T_max, BSI_warning, BSI_high, BSI_trip, ...
    V_max, C_rate_max)

    %% Default factors

    tempFactor = 1.0;
    bsiFactor = 1.0;

    %% ------------------------------------------------------------
    % HARD SAFETY CONDITIONS
    % ------------------------------------------------------------

    if SOC >= SOC_target

        C_target = 0;
        return;

    end

    if Temperature >= T_max

        C_target = 0;
        return;

    end

    if BSI >= BSI_trip

        C_target = 0;
        return;

    end

    if OCV >= V_max

        C_target = 0;
        return;

    end

    %% ------------------------------------------------------------
    % BASE C-RATE BASED ON SOC
    % ------------------------------------------------------------

    if SOC < 0.50

        base_C = 1.5;

    elseif SOC < 0.70

        base_C = 1.2;

    elseif SOC < 0.85

        base_C = 0.9;

    elseif SOC < 0.90

        base_C = 0.7;

    else

        base_C = 0.6;

    end

    %% ------------------------------------------------------------
    % TEMPERATURE DERATING
    % ------------------------------------------------------------

    if Temperature < 28

        tempFactor = 1.00;

    elseif Temperature < 30

        tempFactor = 0.90;

    elseif Temperature < 32

        tempFactor = 0.75;

    elseif Temperature < 35

        tempFactor = 0.55;

    elseif Temperature < T_warning

        tempFactor = 0.35;

    else

        tempFactor = 0.20;

    end

    %% ------------------------------------------------------------
    % BSI DERATING
    % ------------------------------------------------------------

    if BSI < 35

        bsiFactor = 1.00;

    elseif BSI < BSI_warning

        bsiFactor = 0.90;

    elseif BSI < BSI_high

        bsiFactor = 0.75;

    elseif BSI < BSI_trip

        bsiFactor = 0.50;

    else

        bsiFactor = 0.00;

    end

    %% ------------------------------------------------------------
    % SOH DERATING
    % ------------------------------------------------------------

    if SOH >= 0.90

        sohFactor = 1.00;

    elseif SOH >= 0.85

        sohFactor = 0.90;

    elseif SOH >= 0.80

        sohFactor = 0.80;

    else

        sohFactor = 0.60;

    end

    %% ------------------------------------------------------------
    % INDIVIDUAL C-RATE LIMITS
    % ------------------------------------------------------------

    C_temperature = ...
        base_C * tempFactor;

    C_BSI = ...
        base_C * bsiFactor;

    C_SOH = ...
        base_C * sohFactor;

    %% ------------------------------------------------------------
    % FINAL ADAPTIVE C-RATE
    % ------------------------------------------------------------

    C_target = min([ ...
        base_C, ...
        C_temperature, ...
        C_BSI, ...
        C_SOH, ...
        C_rate_max]);

    C_target = ...
        max(C_target,0);

end