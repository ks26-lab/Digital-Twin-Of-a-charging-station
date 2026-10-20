%% ========================================================================
% QUICK START RUNNER: SMART DC FAST CHARGING STATION DIGITAL TWIN
% ========================================================================
% Simply click "Run" (or type "run_project" in the MATLAB Command Window).
%
% This script:
%   1. Automatically sets up the MATLAB paths
%   2. Runs the 3-EV Dynamic Reallocation Scenario
%   3. Displays the 6-Panel Diagnostic Graphs
%   4. Runs the automated test suite
%   5. Launches the Interactive Station Dashboard GUI
% ========================================================================

clearvars;
close all;
clc;

fprintf('========================================================================\n');
fprintf('  STARTING SMART EV CHARGING STATION DIGITAL TWIN\n');
fprintf('========================================================================\n\n');

% Step 1: Configure Paths
repo_root = fileparts(mfilename('fullpath'));
if isempty(repo_root)
    repo_root = pwd;
end
cd(repo_root);

addpath(fullfile(repo_root, 'SmartEVChargingStation'));
addpath(fullfile(repo_root, 'SmartEVChargingStation', 'tests'));
fprintf('[1/4] Added SmartEVChargingStation and tests to MATLAB path.\n');

% Step 2: Run 3-EV Dynamic Reallocation Simulation
fprintf('[2/4] Running 3-EV Dynamic Simulation (EV1 & EV2 charging, EV3 connects at 60s)...\n');
sim_log = simulate_three_ev_scenario();
fprintf('      Simulation complete! Duration: %.1fs, Timestep: %.2fs\n', ...
    sim_log.scen_cfg.t_end, sim_log.scen_cfg.dt);

% Step 3: Plot Diagnostic Results
fprintf('[3/4] Generating 6-panel diagnostic telemetry graphs...\n');
figures_dir = fullfile(repo_root, 'figures');
fig_handles = plot_three_ev_results(sim_log, figures_dir);
fprintf('      Graphs displayed on screen and saved to /figures folder.\n');

% Step 4: Run Automated Verification Tests
fprintf('[4/4] Running automated tests...\n');
results_3ev = test_three_ev_dynamic_reallocation();

fprintf('\n------------------------------------------------------------------------\n');
fprintf('  QUICK COMMANDS TO RUN SPECIFIC COMPONENTS:\n');
fprintf('------------------------------------------------------------------------\n');
fprintf('  station_dashboard()                 - Opens the Interactive GUI Dashboard\n');
fprintf('  test_digital_twin_verification()    - Runs the 11 baseline unit tests\n');
fprintf('  test_three_ev_dynamic_reallocation()- Runs the 7 dynamic scenario tests\n');
fprintf('  build_three_ev_simulink_model()     - Builds the Simulink .slx model\n');
fprintf('------------------------------------------------------------------------\n\n');

% Optional: Launch the Interactive Dashboard GUI
reply = input('Would you like to open the interactive Station Dashboard GUI now? (Y/N) [Y]: ', 's');
if isempty(reply) || strcmpi(reply, 'y')
    fprintf('Launching Station Dashboard GUI...\n');
    station_dashboard();
end
