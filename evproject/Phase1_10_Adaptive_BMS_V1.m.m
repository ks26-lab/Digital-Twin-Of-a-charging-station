%% ================================================================
%  BATTERY-AWARE SMART DC FAST CHARGING STATION
%  PHASES 1-10 MATLAB MODEL
%
%  Project:
%  Adaptive C-Rate Control + Battery Stress Index
%
%  Phases included:
%  1. Battery parameters
%  2. SOC model
%  3. Voltage model
%  4. Temperature model
%  5. SOH + Internal Resistance
%  6. Battery Stress Index (BSI)
%  7. Adaptive C-rate controller
%  8. Safety logic
%  9. Complete closed-loop simulation
% 10. Fixed C-rate vs Adaptive comparison
%
%  IMPORTANT:
%  This is a behavioral/proof-of-concept battery model.
%  It is NOT a validated electrochemical battery model.
% ================================================================

clear;
clc;
close all;

%% ================================================================
%  PHASE 1 - BATTERY PARAMETERS
% ================================================================

% Battery nominal parameters
Q_nom = 50;                 % Nominal capacity [Ah]
V_nom = 48;                 % Nominal pack voltage [V]

% Initial and target conditions
SOC_initial = 0.20;         % Initial SOC = 20%
SOC_target  = 0.95;         % Charging target = 95%

SOH_initial = 0.95;         % Initial SOH = 95%

T_initial = 25;             % Initial temperature [deg C]

% Initial internal resistance
R_initial = 0.05;           % [Ohm]

% Simulation settings
dt = 1;                     % Time step [s]
t_end = 3600;               % Maximum simulation time [s]

% Safety limits
T_warning = 40;             % Temperature warning [deg C]
T_max = 45;                 % Maximum temperature [deg C]

BSI_warning = 50;           % Stress warning
BSI_high = 75;              % High stress
BSI_trip = 90;              % Critical stress

% Voltage limits for this simplified 48-V model
V_min = 42;
V_max = 54;

% Maximum allowable C-rate in this prototype
C_rate_max = 1.5;

% Fixed charging rate for comparison
Fixed_C_rate = 1.0;

% Thermal model parameters
Tamb = 25;                  % Ambient temperature [deg C]
thermal_gain = 1e-4;        % Simplified heating coefficient
cooling_gain = 0.01;        % Simplified cooling coefficient

% SOH degradation coefficient
degradation_coeff = 1e-7;

%% ================================================================
%  DISPLAY BASIC PARAMETERS
% ================================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf(' BATTERY-AWARE SMART DC FAST CHARGING SIMULATION\n');
fprintf('============================================================\n');

fprintf('Battery voltage       : %.1f V\n', V_nom);
fprintf('Battery capacity      : %.1f Ah\n', Q_nom);
fprintf('Initial SOC           : %.1f %%\n', SOC_initial*100);
fprintf('Target SOC            : %.1f %%\n', SOC_target*100);
fprintf('Initial SOH           : %.1f %%\n', SOH_initial*100);
fprintf('Initial temperature   : %.1f deg C\n', T_initial);
fprintf('Initial resistance    : %.4f Ohm\n', R_initial);
fprintf('Maximum C-rate        : %.1f C\n', C_rate_max);
fprintf('Fixed comparison rate : %.1f C\n', Fixed_C_rate);

fprintf('============================================================\n\n');


%% ================================================================
%  RUN ADAPTIVE CHARGING SIMULATION
% ================================================================

adaptive = runAdaptiveSimulation( ...
    Q_nom, SOC_initial, SOC_target, SOH_initial, ...
    T_initial, R_initial, dt, t_end, ...
    T_warning, T_max, ...
    BSI_warning, BSI_high, BSI_trip, ...
    V_min, V_max, C_rate_max, ...
    Tamb, thermal_gain, cooling_gain, ...
    degradation_coeff);


%% ================================================================
%  RUN FIXED C-RATE SIMULATION
% ================================================================

fixed = runFixedSimulation( ...
    Q_nom, SOC_initial, SOC_target, SOH_initial, ...
    T_initial, R_initial, dt, t_end, ...
    T_max, BSI_trip, V_min, V_max, ...
    Fixed_C_rate, Tamb, thermal_gain, ...
    cooling_gain, degradation_coeff);


%% ================================================================
%  PHASE 10 - COMPARISON
% ================================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf(' FINAL RESULTS\n');
fprintf('============================================================\n');

fprintf('\nADAPTIVE CHARGING\n');
fprintf('Charging time       : %.2f minutes\n', adaptive.charge_time/60);
fprintf('Final SOC           : %.2f %%\n', adaptive.SOC_final*100);
fprintf('Final SOH           : %.4f %%\n', adaptive.SOH_final*100);
fprintf('Maximum temperature : %.2f deg C\n', adaptive.T_maximum);
fprintf('Maximum BSI         : %.2f / 100\n', adaptive.BSI_maximum);
fprintf('Maximum current     : %.2f A\n', adaptive.I_maximum);
fprintf('Energy delivered    : %.3f kWh\n', adaptive.energy_kWh);

fprintf('\nFIXED %.1fC CHARGING\n', Fixed_C_rate);
fprintf('Charging time       : %.2f minutes\n', fixed.charge_time/60);
fprintf('Final SOC           : %.2f %%\n', fixed.SOC_final*100);
fprintf('Final SOH           : %.4f %%\n', fixed.SOH_final*100);
fprintf('Maximum temperature : %.2f deg C\n', fixed.T_maximum);
fprintf('Maximum BSI         : %.2f / 100\n', fixed.BSI_maximum);
fprintf('Maximum current     : %.2f A\n', fixed.I_maximum);
fprintf('Energy delivered    : %.3f kWh\n', fixed.energy_kWh);


%% ================================================================
%  COMPARISON TABLE
% ================================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf(' ADAPTIVE vs FIXED CHARGING\n');
fprintf('============================================================\n');

fprintf('\n');
fprintf('%-25s %-15s %-15s\n', ...
    'Parameter','Adaptive','Fixed');
fprintf('%s\n', repmat('-',1,58));

fprintf('%-25s %-15.2f %-15.2f\n', ...
    'Charging time (min)', ...
    adaptive.charge_time/60, ...
    fixed.charge_time/60);

fprintf('%-25s %-15.2f %-15.2f\n', ...
    'Final SOC (%)', ...
    adaptive.SOC_final*100, ...
    fixed.SOC_final*100);

fprintf('%-25s %-15.4f %-15.4f\n', ...
    'Final SOH (%)', ...
    adaptive.SOH_final*100, ...
    fixed.SOH_final*100);

fprintf('%-25s %-15.2f %-15.2f\n', ...
    'Max temperature (C)', ...
    adaptive.T_maximum, ...
    fixed.T_maximum);

fprintf('%-25s %-15.2f %-15.2f\n', ...
    'Max BSI', ...
    adaptive.BSI_maximum, ...
    fixed.BSI_maximum);

fprintf('%-25s %-15.2f %-15.2f\n', ...
    'Max current (A)', ...
    adaptive.I_maximum, ...
    fixed.I_maximum);

fprintf('%-25s %-15.3f %-15.3f\n', ...
    'Energy (kWh)', ...
    adaptive.energy_kWh, ...
    fixed.energy_kWh);

fprintf('============================================================\n');


%% ================================================================
%  PHASE 9 - PLOT ADAPTIVE CHARGING RESULTS
% ================================================================

figure('Name','Adaptive Charging Results');

subplot(3,2,1);

plot(adaptive.time, adaptive.SOC*100, 'LineWidth', 1.5);
grid on;
xlabel('Time (s)');
ylabel('SOC (%)');
title('Battery SOC');

subplot(3,2,2);

plot(adaptive.time, adaptive.Voltage, 'LineWidth', 1.5);
grid on;
xlabel('Time (s)');
ylabel('Voltage (V)');
title('Battery Voltage');

subplot(3,2,3);

plot(adaptive.time, adaptive.Current, 'LineWidth', 1.5);
grid on;
xlabel('Time (s)');
ylabel('Current (A)');
title('Adaptive Charging Current');

subplot(3,2,4);

plot(adaptive.time, adaptive.C_rate, 'LineWidth', 1.5);
grid on;
xlabel('Time (s)');
ylabel('C-rate');
title('Adaptive C-rate');

subplot(3,2,5);

plot(adaptive.time, adaptive.Temperature, 'LineWidth', 1.5);
grid on;
xlabel('Time (s)');
ylabel('Temperature (deg C)');
title('Battery Temperature');

subplot(3,2,6);

plot(adaptive.time, adaptive.BSI, 'LineWidth', 1.5);
grid on;
xlabel('Time (s)');
ylabel('BSI');
title('Battery Stress Index');


%% ================================================================
%  SOH / RESISTANCE PLOTS
% ================================================================

figure('Name','Battery Health');

subplot(2,1,1);

plot(adaptive.time, adaptive.SOH*100, 'LineWidth', 1.5);
grid on;
xlabel('Time (s)');
ylabel('SOH (%)');
title('Battery State of Health');

subplot(2,1,2);

plot(adaptive.time, adaptive.Rint, 'LineWidth', 1.5);
grid on;
xlabel('Time (s)');
ylabel('Resistance (Ohm)');
title('Internal Resistance');


%% ================================================================
%  FIXED vs ADAPTIVE CURRENT
% ================================================================

figure('Name','Fixed vs Adaptive Charging');

plot(adaptive.time/60, adaptive.Current, ...
    'LineWidth',1.5);

hold on;

plot(fixed.time/60, fixed.Current, ...
    'LineWidth',1.5);

grid on;

xlabel('Time (min)');
ylabel('Charging Current (A)');

title('Fixed vs Adaptive Charging Current');

legend('Adaptive','Fixed 1C','Location','best');


%% ================================================================
%  FIXED vs ADAPTIVE TEMPERATURE
% ================================================================

figure('Name','Temperature Comparison');

plot(adaptive.time/60, adaptive.Temperature, ...
    'LineWidth',1.5);

hold on;

plot(fixed.time/60, fixed.Temperature, ...
    'LineWidth',1.5);

grid on;

xlabel('Time (min)');
ylabel('Temperature (deg C)');

title('Fixed vs Adaptive Temperature');

legend('Adaptive','Fixed','Location','best');


%% ================================================================
%  FIXED vs ADAPTIVE BSI
% ================================================================

figure('Name','BSI Comparison');

plot(adaptive.time/60, adaptive.BSI, ...
    'LineWidth',1.5);

hold on;

plot(fixed.time/60, fixed.BSI, ...
    'LineWidth',1.5);

grid on;

xlabel('Time (min)');
ylabel('Battery Stress Index');

title('Fixed vs Adaptive Battery Stress');

legend('Adaptive','Fixed','Location','best');


%% ================================================================
%  SAVE SIMULATION DATA
% ================================================================

adaptive_table = table( ...
    adaptive.time', ...
    adaptive.SOC', ...
    adaptive.Voltage', ...
    adaptive.Current', ...
    adaptive.Temperature', ...
    adaptive.SOH', ...
    adaptive.Rint', ...
    adaptive.C_rate', ...
    adaptive.BSI', ...
    'VariableNames', { ...
    'Time_s', ...
    'SOC', ...
    'Voltage_V', ...
    'Current_A', ...
    'Temperature_C', ...
    'SOH', ...
    'InternalResistance_Ohm', ...
    'C_rate', ...
    'BSI'});

fixed_table = table( ...
    fixed.time', ...
    fixed.SOC', ...
    fixed.Voltage', ...
    fixed.Current', ...
    fixed.Temperature', ...
    fixed.SOH', ...
    fixed.Rint', ...
    fixed.C_rate', ...
    fixed.BSI', ...
    'VariableNames', { ...
    'Time_s', ...
    'SOC', ...
    'Voltage_V', ...
    'Current_A', ...
    'Temperature_C', ...
    'SOH', ...
    'InternalResistance_Ohm', ...
    'C_rate', ...
    'BSI'});

writetable(adaptive_table, ...
    'adaptive_simulation_data.csv');

writetable(fixed_table, ...
    'fixed_simulation_data.csv');

fprintf('\nSimulation files saved:\n');
fprintf('  adaptive_simulation_data.csv\n');
fprintf('  fixed_simulation_data.csv\n');


%% ================================================================
%  END OF MAIN SCRIPT
% ================================================================



%% ################################################################
%  FUNCTION 1
%  ADAPTIVE CHARGING SIMULATION
% #################################################################

function result = runAdaptiveSimulation( ...
    Q_nom, SOC_initial, SOC_target, SOH_initial, ...
    T_initial, R_initial, dt, t_end, ...
    T_warning, T_max, ...
    BSI_warning, BSI_high, BSI_trip, ...
    V_min, V_max, C_rate_max, ...
    Tamb, thermal_gain, cooling_gain, ...
    degradation_coeff)

    % Time vector
    time = 0:dt:t_end;
    N = length(time);

    % Allocate memory
    SOC = zeros(1,N);
    Voltage = zeros(1,N);
    Current = zeros(1,N);
    Temperature = zeros(1,N);
    SOH = zeros(1,N);
    Rint = zeros(1,N);
    C_rate = zeros(1,N);
    BSI = zeros(1,N);

    % Initial values
    SOC(1) = SOC_initial;
    Temperature(1) = T_initial;
    SOH(1) = SOH_initial;
    Rint(1) = R_initial;

    % Safety/status
    charge_complete = false;

    %% Main simulation loop

    for k = 1:N-1

        % ------------------------------------------------------------
        % STEP 1: Estimate internal resistance
        % ------------------------------------------------------------

        soc_factor = 1 + ...
            0.20*abs(SOC(k)-0.50);

        soh_factor = 1 + ...
            (1-SOH(k));

        temp_factor = 1 + ...
            0.01*max(Temperature(k)-25,0);

        Rint(k) = R_initial * ...
            soc_factor * ...
            soh_factor * ...
            temp_factor;


        % ------------------------------------------------------------
        % STEP 2: Calculate BSI components
        % ------------------------------------------------------------

        % Current C-rate from previous current
        C_previous = Current(k)/Q_nom;

        % C-rate stress
        stress_C = abs(C_previous)/C_rate_max;

        % Temperature stress
        stress_T = ...
            max(0,(Temperature(k)-25)/(T_max-25));

        % SOC stress
        if SOC(k) < 0.70
            stress_SOC = 0.20;
        elseif SOC(k) < 0.85
            stress_SOC = 0.50;
        else
            stress_SOC = 0.90;
        end

        % Resistance stress
        stress_R = ...
            min(max((Rint(k)/R_initial - 1),0),1);

        % SOH stress
        stress_SOH = ...
            min(max((1-SOH(k))/0.30,0),1);

        % ------------------------------------------------------------
        % BSI weighting
        % ------------------------------------------------------------

        wC = 0.35;
        wT = 0.30;
        wSOC = 0.20;
        wR = 0.15;

        BSI(k) = 100*( ...
            wC*stress_C + ...
            wT*stress_T + ...
            wSOC*stress_SOC + ...
            wR*max(stress_R,stress_SOH));

        BSI(k) = min(max(BSI(k),0),100);


        % ------------------------------------------------------------
        % STEP 3: Adaptive C-rate controller
        % ------------------------------------------------------------

        if SOC(k) >= SOC_target

            C_target = 0;

        elseif Temperature(k) >= T_max

            C_target = 0;

        elseif BSI(k) >= BSI_trip

            C_target = 0;

        elseif Voltage(k) >= V_max

            C_target = 0;

        elseif SOH(k) < 0.80

            C_target = 0.5;

        elseif Temperature(k) >= T_warning

            C_target = 0.5;

        elseif BSI(k) >= BSI_high

            C_target = 0.5;

        elseif BSI(k) >= BSI_warning

            C_target = 0.8;

        elseif SOC(k) >= 0.85

            C_target = 0.8;

        elseif SOC(k) >= 0.70

            C_target = 1.2;

        else

            C_target = 1.5;

        end


        % ------------------------------------------------------------
        % STEP 4: Convert C-rate to current
        % ------------------------------------------------------------

        Current(k) = C_target * Q_nom;

        C_rate(k) = Current(k)/Q_nom;


        % ------------------------------------------------------------
        % STEP 5: Battery voltage model
        % ------------------------------------------------------------

        % Simple OCV-SOC relationship
        OCV = 42 + 6*SOC(k);

        % Terminal voltage during charging
        Voltage(k) = OCV + Current(k)*Rint(k);


        % ------------------------------------------------------------
        % STEP 6: Temperature model
        % ------------------------------------------------------------

        % Resistive heating
        P_loss = Current(k)^2 * Rint(k);

        heating = thermal_gain * P_loss;

        cooling = cooling_gain * ...
            (Temperature(k)-Tamb);

        Temperature(k+1) = ...
            Temperature(k) + ...
            heating - cooling;


        % ------------------------------------------------------------
        % STEP 7: SOC update
        % ------------------------------------------------------------

        dSOC = Current(k)*dt/(Q_nom*3600);

        SOC(k+1) = SOC(k) + dSOC;

        SOC(k+1) = min(max(SOC(k+1),0),1);


        % ------------------------------------------------------------
        % STEP 8: SOH degradation model
        % ------------------------------------------------------------

        degradation = ...
            degradation_coeff * ...
            (Current(k)/Q_nom)^2;

        % Additional temperature degradation
        if Temperature(k) > 35

            degradation = degradation * ...
                (1 + 0.1*(Temperature(k)-35));

        end

        SOH(k+1) = SOH(k) - degradation;

        SOH(k+1) = min(max(SOH(k+1),0),1);


        % ------------------------------------------------------------
        % STEP 9: Check charge completion
        % ------------------------------------------------------------

        if SOC(k+1) >= SOC_target

            SOC(k+1) = SOC_target;

            Current(k+1) = 0;

            C_rate(k+1) = 0;

            charge_complete = true;

            % Fill remaining arrays with final values
            SOC(k+2:end) = SOC_target;
            Temperature(k+2:end) = Temperature(k+1);
            SOH(k+2:end) = SOH(k+1);
            Rint(k+1:end) = Rint(k);
            Voltage(k+1:end) = Voltage(k);

            break;
        end

    end


    % ------------------------------------------------------------
    % Calculate final BSI point
    % ------------------------------------------------------------

    last = find(SOC > 0,1,'last');

    if isempty(last)
        last = 1;
    end

    % Calculate remaining values
    for k = 1:last

        if Rint(k) == 0
            Rint(k) = R_initial;
        end

    end

    % ------------------------------------------------------------
    % Determine actual charging time
    % ------------------------------------------------------------

    charge_index = find(SOC >= SOC_target,1);

    if isempty(charge_index)

        charge_time = time(end);

    else

        charge_time = time(charge_index);

    end


    % ------------------------------------------------------------
    % Calculate energy
    % ------------------------------------------------------------

    power = Voltage .* Current;

    energy_J = trapz(time,power);

    energy_Wh = energy_J / 3600;

    energy_kWh = energy_Wh / 1000;


    % ------------------------------------------------------------
    % Result structure
    % ------------------------------------------------------------

    result.time = time;

    result.SOC = SOC;
    result.Voltage = Voltage;
    result.Current = Current;
    result.Temperature = Temperature;
    result.SOH = SOH;
    result.Rint = Rint;
    result.C_rate = C_rate;
    result.BSI = BSI;

    result.SOC_final = SOC(charge_index);
    result.SOH_final = SOH(charge_index);

    result.T_maximum = max(Temperature);
    result.BSI_maximum = max(BSI);
    result.I_maximum = max(Current);

    result.energy_kWh = energy_kWh;

    result.charge_time = charge_time;

end



%% ################################################################
%  FUNCTION 2
%  FIXED C-RATE SIMULATION
% #################################################################

function result = runFixedSimulation( ...
    Q_nom, SOC_initial, SOC_target, SOH_initial, ...
    T_initial, R_initial, dt, t_end, ...
    T_max, BSI_trip, V_min, V_max, ...
    Fixed_C_rate, Tamb, thermal_gain, ...
    cooling_gain, degradation_coeff)

    % Time vector
    time = 0:dt:t_end;
    N = length(time);

    % Allocate arrays
    SOC = zeros(1,N);
    Voltage = zeros(1,N);
    Current = zeros(1,N);
    Temperature = zeros(1,N);
    SOH = zeros(1,N);
    Rint = zeros(1,N);
    C_rate = zeros(1,N);
    BSI = zeros(1,N);

    % Initial values
    SOC(1) = SOC_initial;
    Temperature(1) = T_initial;
    SOH(1) = SOH_initial;
    Rint(1) = R_initial;

    %% Simulation loop

    for k = 1:N-1

        % ------------------------------------------------------------
        % Internal resistance
        % ------------------------------------------------------------

        soc_factor = ...
            1 + 0.20*abs(SOC(k)-0.50);

        soh_factor = ...
            1 + (1-SOH(k));

        temp_factor = ...
            1 + 0.01*max(Temperature(k)-25,0);

        Rint(k) = R_initial * ...
            soc_factor * ...
            soh_factor * ...
            temp_factor;


        % ------------------------------------------------------------
        % Fixed charging current
        % ------------------------------------------------------------

        Current(k) = Fixed_C_rate * Q_nom;

        C_rate(k) = Fixed_C_rate;


        % ------------------------------------------------------------
        % Voltage
        % ------------------------------------------------------------

        OCV = 42 + 6*SOC(k);

        Voltage(k) = ...
            OCV + Current(k)*Rint(k);


        % ------------------------------------------------------------
        % BSI
        % ------------------------------------------------------------

        stress_C = Fixed_C_rate/1.5;

        stress_T = ...
            max(0,(Temperature(k)-25)/(T_max-25));

        if SOC(k) < 0.70
            stress_SOC = 0.20;
        elseif SOC(k) < 0.85
            stress_SOC = 0.50;
        else
            stress_SOC = 0.90;
        end

        stress_R = ...
            min(max((Rint(k)/R_initial - 1),0),1);

        stress_SOH = ...
            min(max((1-SOH(k))/0.30,0),1);

        BSI(k) = 100*( ...
            0.35*stress_C + ...
            0.30*stress_T + ...
            0.20*stress_SOC + ...
            0.15*max(stress_R,stress_SOH));

        BSI(k) = min(max(BSI(k),0),100);


        % ------------------------------------------------------------
        % Safety logic
        % ------------------------------------------------------------

        if Temperature(k) >= T_max || ...
           BSI(k) >= BSI_trip || ...
           Voltage(k) >= V_max

            Current(k) = 0;
            C_rate(k) = 0;

        end


        % ------------------------------------------------------------
        % Temperature
        % ------------------------------------------------------------

        P_loss = Current(k)^2 * Rint(k);

        heating = thermal_gain * P_loss;

        cooling = cooling_gain * ...
            (Temperature(k)-Tamb);

        Temperature(k+1) = ...
            Temperature(k) + ...
            heating - cooling;


        % ------------------------------------------------------------
        % SOC
        % ------------------------------------------------------------

        dSOC = Current(k)*dt/(Q_nom*3600);

        SOC(k+1) = ...
            SOC(k) + dSOC;

        SOC(k+1) = ...
            min(max(SOC(k+1),0),1);


        % ------------------------------------------------------------
        % SOH degradation
        % ------------------------------------------------------------

        degradation = ...
            degradation_coeff * ...
            (Current(k)/Q_nom)^2;

        if Temperature(k) > 35

            degradation = degradation * ...
                (1 + 0.1*(Temperature(k)-35));

        end

        SOH(k+1) = ...
            SOH(k) - degradation;

        SOH(k+1) = ...
            min(max(SOH(k+1),0),1);


        % ------------------------------------------------------------
        % Stop at target SOC
        % ------------------------------------------------------------

        if SOC(k+1) >= SOC_target

            SOC(k+1) = SOC_target;

            Current(k+1) = 0;

            C_rate(k+1) = 0;

            SOC(k+2:end) = SOC_target;
            Temperature(k+2:end) = Temperature(k+1);
            SOH(k+2:end) = SOH(k+1);
            Rint(k+1:end) = Rint(k);
            Voltage(k+1:end) = Voltage(k);

            break;

        end

    end


    % ------------------------------------------------------------
    % Charging time
    % ------------------------------------------------------------

    charge_index = find(SOC >= SOC_target,1);

    if isempty(charge_index)

        charge_time = time(end);

    else

        charge_time = time(charge_index);

    end


    % ------------------------------------------------------------
    % Energy
    % ------------------------------------------------------------

    power = Voltage .* Current;

    energy_J = trapz(time, power);

    energy_Wh = energy_J / 3600;

    energy_kWh = energy_Wh / 1000;

    % ------------------------------------------------------------
    % Results
    % ------------------------------------------------------------

    result.time = time;

    result.SOC = SOC;
    result.Voltage = Voltage;
    result.Current = Current;
    result.Temperature = Temperature;
    result.SOH = SOH;
    result.Rint = Rint;
    result.C_rate = C_rate;
    result.BSI = BSI;

    result.SOC_final = SOC(charge_index);
    result.SOH_final = SOH(charge_index);

    result.T_maximum = max(Temperature);
    result.BSI_maximum = max(BSI);
    result.I_maximum = max(Current);

    result.energy_kWh = energy_kWh;

    result.charge_time = charge_time;

end
