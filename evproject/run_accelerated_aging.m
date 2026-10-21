% --- ACCELERATED AGING & ML DATASET GENERATOR ---

model_name = 'Smart_DC_Fast_Charging';

% 1. Initial Battery State (Brand New, 100% Health)
var_SOH = 1.0;     
var_Q = 50;        
var_R = 0.050;     

% 2. Simulation Settings
num_loops = 50;           % Run the simulation 50 times
cycles_per_loop = 20;     % Each run acts as a time-jump representing 20 fast charges

% Arrays to store our generated ML dataset
history_Cycle = zeros(num_loops, 1);
history_SOH = zeros(num_loops, 1);
history_Capacity = zeros(num_loops, 1);
history_Resistance = zeros(num_loops, 1);

fprintf('Starting Accelerated Aging Simulation...\n');

for i = 1:num_loops
    % Push the aging parameters to the base workspace for Simulink to read
    assignin('base', 'var_SOH', var_SOH);
    assignin('base', 'var_Q', var_Q);
    assignin('base', 'var_R', var_R);

    % Run the 2-hour fast charge cycle silently
    out = sim(model_name, 'ReturnWorkspaceOutputs', 'on');

    % Extract the exact amount of health lost during this single charge
    final_SOH = out.SOH_smart.Data(end);
    degradation_per_charge = var_SOH - final_SOH;

    % Time-jump: Multiply the single-cycle wear by our acceleration factor
    total_degradation = degradation_per_charge * cycles_per_loop;

    % Update Battery Physics for the NEXT loop
    var_SOH = var_SOH - total_degradation;
    var_Q = 50 * var_SOH; % Capacity drops as SOH drops
    var_R = 0.050 * (1 + 2 * (1 - var_SOH)); % Resistance slowly grows

    % Log the data for Phase 11 (ML Generation)
    history_Cycle(i) = i * cycles_per_loop;
    history_SOH(i) = var_SOH;
    history_Capacity(i) = var_Q;
    history_Resistance(i) = var_R;

    fprintf('Time-Jump Complete: Cycle %d | SOH: %.3f%% | Cap: %.2f Ah\n', history_Cycle(i), var_SOH*100, var_Q);
end

% 3. Plot the Long-Term Degradation Curve
figure('Name', 'Long-Term Battery Degradation', 'Color', 'w');
subplot(2,1,1);
plot(history_Cycle, history_SOH * 100, '-b', 'LineWidth', 2);
title('Battery State of Health (SOH) Over 1,000 Fast Charges');
ylabel('SOH (%)'); grid on;

subplot(2,1,2);
plot(history_Cycle, history_Capacity, '-r', 'LineWidth', 2);
title('Usable Capacity Fade (Ah)');
xlabel('Total Charge Cycles'); ylabel('Capacity (Ah)'); grid on;