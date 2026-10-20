function fig_handles = plot_three_ev_results(sim_log, save_path)
% PLOT_THREE_EV_RESULTS Generates comprehensive multi-panel diagnostic plots
% for the 3-EV dynamic charging, connection gating, and BMS verification scenario.
%
% Generates:
%   Figure 1: Full 6-Panel Time Series Telemetry
%     Panel 1: Charging Current delivered to EV 1, 2, 3 (A)
%     Panel 2: Allocated vs Delivered Power per EV (kW)
%     Panel 3: Station Total Power vs Station Power Budget (kW)
%     Panel 4: Battery State of Charge (SOC %) for all 3 EVs
%     Panel 5: EV 3 Lifecycle State Timeline (Connection & BMS Verification)
%     Panel 6: Multi-tier Current Comparison for EV 3 (Req, BMS, Alloc, Cmd, Deliv)
%
% Usage:
%   plot_three_ev_results();                  % Runs default scenario and plots
%   plot_three_ev_results(sim_log);           % Plots provided log
%   plot_three_ev_results(sim_log, 'plots/'); % Saves figures to path

if nargin < 1 || isempty(sim_log)
    fprintf('No simulation log provided. Running default 3-EV simulation...\n');
    sim_log = simulate_three_ev_scenario();
end

if nargin < 2
    save_path = '';
end

t = sim_log.time;
t_conn = sim_log.scen_cfg.t_connect;
t_veri = sim_log.scen_cfg.t_verify;

% Color Palette for Publication-Quality Aesthetics
c_ev1 = [0.12, 0.47, 0.71]; % Blue
c_ev2 = [0.20, 0.63, 0.17]; % Green
c_ev3 = [0.89, 0.10, 0.11]; % Red
c_lim = [0.45, 0.45, 0.45]; % Charcoal Gray
c_amb = [0.95, 0.50, 0.10]; % Amber

fig_handles = [];

%% ========================================================================
%% FIGURE 1: 6-PANEL HIGH-RESOLUTION TELEMETRY
%% ========================================================================
f1 = figure('Name', 'Three-EV Dynamic Reallocation & BMS Verification Telemetry', ...
            'Color', 'w', 'Position', [80, 50, 1100, 850]);
fig_handles(end+1) = f1;

% --- Panel 1: Delivered Charging Currents ---
subplot(3, 2, 1);
plot(t, sim_log.I_delivered(:, 1), 'LineWidth', 2.0, 'Color', c_ev1); hold on;
plot(t, sim_log.I_delivered(:, 2), 'LineWidth', 2.0, 'Color', c_ev2);
plot(t, sim_log.I_delivered(:, 3), 'LineWidth', 2.2, 'Color', c_ev3);
xline(t_conn, '--k', 'EV3 Plug Locked', 'LineWidth', 1.2, 'LabelOrientation', 'aligned');
xline(t_veri, '-.m', 'BMS Verified', 'LineWidth', 1.2, 'LabelOrientation', 'aligned');
grid on; box on;
xlabel('Time (seconds)', 'FontSize', 9);
ylabel('Current (A)', 'FontSize', 9);
title('(a) Delivered Charging Current per EV (A)', 'FontSize', 10, 'FontWeight', 'bold');
legend({'EV 1 (50 Ah, 70% Initial SOC)', 'EV 2 (40 Ah, 80% Initial SOC)', 'EV 3 (65 Ah, 70% Initial SOC)'}, ...
    'Location', 'best', 'FontSize', 8);

% --- Panel 2: Allocated vs Delivered Power per EV ---
subplot(3, 2, 2);
plot(t, sim_log.P_delivered(:, 1), 'LineWidth', 1.8, 'Color', c_ev1); hold on;
plot(t, sim_log.P_delivered(:, 2), 'LineWidth', 1.8, 'Color', c_ev2);
plot(t, sim_log.P_delivered(:, 3), 'LineWidth', 1.8, 'Color', c_ev3);
plot(t, sim_log.P_allocated(:, 1), ':', 'LineWidth', 1.2, 'Color', c_ev1);
plot(t, sim_log.P_allocated(:, 2), ':', 'LineWidth', 1.2, 'Color', c_ev2);
plot(t, sim_log.P_allocated(:, 3), ':', 'LineWidth', 1.2, 'Color', c_ev3);
xline(t_conn, '--k', 'LineWidth', 1.0);
xline(t_veri, '-.m', 'LineWidth', 1.0);
grid on; box on;
xlabel('Time (seconds)', 'FontSize', 9);
ylabel('Power (kW)', 'FontSize', 9);
title('(b) EV Active Power: Delivered (solid) vs Allocated (dotted)', 'FontSize', 10, 'FontWeight', 'bold');
legend({'P_{deliv} EV1', 'P_{deliv} EV2', 'P_{deliv} EV3'}, 'Location', 'best', 'FontSize', 8);

% --- Panel 3: Station Total Power vs Grid Budget ---
subplot(3, 2, 3);
plot(t, sim_log.P_station_total, 'LineWidth', 2.2, 'Color', [0.15, 0.15, 0.55]); hold on;
plot(t, sim_log.P_station_limit, '--', 'LineWidth', 2.0, 'Color', [0.85, 0.20, 0.10]);
xline(t_conn, '--k', 'LineWidth', 1.0);
xline(t_veri, '-.m', 'LineWidth', 1.0);
grid on; box on;
ylim([0, max(sim_log.P_station_limit) * 1.25]);
xlabel('Time (seconds)', 'FontSize', 9);
ylabel('Station Power (kW)', 'FontSize', 9);
title('(c) Total Station Grid Load vs Configured Power Budget', 'FontSize', 10, 'FontWeight', 'bold');
legend({'Total Station Power P_{total}', sprintf('Station Budget (%.1f kW)', sim_log.scen_cfg.P_station)}, ...
    'Location', 'best', 'FontSize', 8);

% --- Panel 4: Battery State of Charge (SOC %) ---
subplot(3, 2, 4);
plot(t, sim_log.SOC(:, 1), 'LineWidth', 2.0, 'Color', c_ev1); hold on;
plot(t, sim_log.SOC(:, 2), 'LineWidth', 2.0, 'Color', c_ev2);
plot(t, sim_log.SOC(:, 3), 'LineWidth', 2.0, 'Color', c_ev3);
xline(t_conn, '--k', 'LineWidth', 1.0);
xline(t_veri, '-.m', 'LineWidth', 1.0);
grid on; box on;
xlabel('Time (seconds)', 'FontSize', 9);
ylabel('SOC (%)', 'FontSize', 9);
title('(d) Battery State of Charge Progression (SOC %)', 'FontSize', 10, 'FontWeight', 'bold');
legend({'EV 1 SOC', 'EV 2 SOC', 'EV 3 SOC'}, 'Location', 'best', 'FontSize', 8);

% --- Panel 5: EV 3 Connection & BMS State Timeline ---
subplot(3, 2, 5);
% Encode state numerically for discrete timeline plotting:
% 0: Disconnected, 1: Plug Locked (Verification Pending), 2: BMS Authorized (Charging), -1: Rejected
state_num = zeros(length(t), 1);
for k = 1:length(t)
    if strcmpi(sim_log.bms_auth(k, 3), "AUTHORIZED")
        state_num(k) = 2;
    elseif strcmpi(sim_log.bms_auth(k, 3), "REJECTED")
        state_num(k) = -1;
    elseif strcmpi(sim_log.bms_auth(k, 3), "PENDING_VERIFICATION")
        state_num(k) = 1;
    else
        state_num(k) = 0;
    end
end
stairs(t, state_num, 'LineWidth', 2.2, 'Color', [0.4, 0.1, 0.6]); hold on;
yline(1, ':k', 'Pending (I = 0A)');
yline(2, ':g', 'Authorized (Charging)');
yline(0, ':b', 'Disconnected');
grid on; box on;
ylim([-1.5, 2.5]);
yticks([-1, 0, 1, 2]);
yticklabels({'FAULT / REJECTED', 'DISCONNECTED', 'PENDING VERIFY', 'AUTHORIZED'});
xlabel('Time (seconds)', 'FontSize', 9);
ylabel('Verification State', 'FontSize', 9);
title('(e) EV 3 Connection & BMS Authorization State Machine', 'FontSize', 10, 'FontWeight', 'bold');

% --- Panel 6: Multi-tier Current Comparison for EV 3 ---
subplot(3, 2, 6);
plot(t, sim_log.I_requested(:, 3), '--', 'LineWidth', 1.2, 'Color', [0.6, 0.6, 0.6]); hold on;
plot(t, sim_log.I_bms_appr(:, 3), '-.', 'LineWidth', 1.6, 'Color', c_amb);
plot(t, sim_log.I_allocated(:, 3), ':', 'LineWidth', 1.6, 'Color', [0.1, 0.6, 0.8]);
plot(t, sim_log.I_commanded(:, 3), '--', 'LineWidth', 1.8, 'Color', [0.5, 0.1, 0.7]);
plot(t, sim_log.I_delivered(:, 3), '-', 'LineWidth', 2.2, 'Color', c_ev3);
xline(t_conn, '--k', 'LineWidth', 1.0);
xline(t_veri, '-.m', 'LineWidth', 1.0);
grid on; box on;
xlabel('Time (seconds)', 'FontSize', 9);
ylabel('Current (A)', 'FontSize', 9);
title('(f) EV 3 Hierarchical Currents (Gating & Throttling)', 'FontSize', 10, 'FontWeight', 'bold');
legend({'1. I_{requested} (Unconstrained)', ...
        '2. I_{BMS\_appr} (BMS Limit)', ...
        '3. I_{allocated} (Grid Limit)', ...
        '4. I_{commanded} (Slew Limited)', ...
        '5. I_{delivered} (Actual Output)'}, ...
        'Location', 'best', 'FontSize', 7.5);

sgtitle('Smart DC Fast Charging Station: 3-EV Dynamic Reallocation & BMS Verification', ...
    'FontSize', 12, 'FontWeight', 'bold');

%% ========================================================================
%% FIGURE 2: SCENARIO COMPARISON (TEST 1: 70% SOC vs TEST 2: 20% SOC)
%% ========================================================================
% Run Test 2 for direct visual comparison
scen2_cfg = sim_log.scen_cfg;
scen2_cfg.ev3.initial_SOC = 0.20; % 20% SOC arrival
log2 = simulate_three_ev_scenario(scen2_cfg);

f2 = figure('Name', 'Comparative Analysis: Test 1 (70% SOC) vs Test 2 (20% SOC)', ...
            'Color', 'w', 'Position', [120, 90, 1000, 600]);
fig_handles(end+1) = f2;

% Subplot A: EV 3 Current Comparison
subplot(2, 2, 1);
plot(t, sim_log.I_delivered(:, 3), 'LineWidth', 2.0, 'Color', c_ev3); hold on;
plot(log2.time, log2.I_delivered(:, 3), 'LineWidth', 2.0, 'Color', [0.1, 0.2, 0.8]);
xline(t_conn, '--k', 'LineWidth', 1.0);
xline(t_veri, '-.m', 'LineWidth', 1.0);
grid on; box on;
xlabel('Time (seconds)'); ylabel('Current (A)');
title('(a) EV 3 Delivered Current: 70% vs 20% SOC', 'FontWeight', 'bold');
legend({'Test 1 (EV3 Initial SOC = 70%)', 'Test 2 (EV3 Initial SOC = 20%)'}, 'Location', 'best');

% Subplot B: EV 1 Current Throttling Comparison
subplot(2, 2, 2);
plot(t, sim_log.I_delivered(:, 1), 'LineWidth', 2.0, 'Color', c_ev1); hold on;
plot(log2.time, log2.I_delivered(:, 1), '--', 'LineWidth', 2.0, 'Color', [0.1, 0.2, 0.8]);
xline(t_conn, '--k', 'LineWidth', 1.0);
xline(t_veri, '-.m', 'LineWidth', 1.0);
grid on; box on;
xlabel('Time (seconds)'); ylabel('Current (A)');
title('(b) EV 1 Current Response to EV 3 Arrival', 'FontWeight', 'bold');
legend({'EV 1 with EV 3 at 70% SOC', 'EV 1 with EV 3 at 20% SOC'}, 'Location', 'best');

% Subplot C: Station Power Total
subplot(2, 2, 3);
plot(t, sim_log.P_station_total, 'LineWidth', 2.0, 'Color', [0.2, 0.5, 0.2]); hold on;
plot(log2.time, log2.P_station_total, '--', 'LineWidth', 2.0, 'Color', [0.7, 0.3, 0.1]);
plot(t, sim_log.P_station_limit, '-.k', 'LineWidth', 1.5);
grid on; box on;
xlabel('Time (seconds)'); ylabel('Power (kW)');
title('(c) Station Power: Test 1 vs Test 2', 'FontWeight', 'bold');
legend({'P_{station} (Test 1)', 'P_{station} (Test 2)', 'Power Limit (10 kW)'}, 'Location', 'best');

% Subplot D: EV 3 Energy Delivered
subplot(2, 2, 4);
plot(t, sim_log.Energy_kWh(:, 3), 'LineWidth', 2.0, 'Color', c_ev3); hold on;
plot(log2.time, log2.Energy_kWh(:, 3), 'LineWidth', 2.0, 'Color', [0.1, 0.2, 0.8]);
grid on; box on;
xlabel('Time (seconds)'); ylabel('Energy (kWh)');
title('(d) Accumulated Energy Transferred to EV 3', 'FontWeight', 'bold');
legend({'Energy EV 3 (70% SOC)', 'Energy EV 3 (20% SOC)'}, 'Location', 'best');

sgtitle('Comparison of Reallocation Dynamics: Test 1 (Similar SOC) vs Test 2 (Low SOC)', ...
    'FontSize', 12, 'FontWeight', 'bold');

%% Save Figures if Path Provided
if ~isempty(save_path)
    if ~exist(save_path, 'dir'); mkdir(save_path); end
    saveas(f1, fullfile(save_path, 'three_ev_dynamic_telemetry.png'));
    saveas(f2, fullfile(save_path, 'three_ev_comparison_70_vs_20_soc.png'));
    fprintf('Plots saved successfully to: %s\n', save_path);
end

end
