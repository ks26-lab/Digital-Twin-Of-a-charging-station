% --- TIME-MACHINE 2.0: THERMAL & BSI DATA EXTRACTION ---

model_name = 'Smart_DC_Fast_Charging';

% Initial Conditions
var_SOH = 1.0; var_Q = 50; var_R = 0.050;     
num_loops = 50; cycles_per_loop = 20;     

% Data arrays for the new ML Dataset
history_Cycle = zeros(num_loops, 1);
history_SOH = zeros(num_loops, 1);
history_Resistance = zeros(num_loops, 1);
history_MaxTemp = zeros(num_loops, 1);
history_MaxBSI = zeros(num_loops, 1);

fprintf('Generating Thermal & BSI Training Data (This will take a minute)...\n');

for i = 1:num_loops
    assignin('base', 'var_SOH', var_SOH);
    assignin('base', 'var_Q', var_Q);
    assignin('base', 'var_R', var_R);

    % Run simulation silently
    out = sim(model_name, 'ReturnWorkspaceOutputs', 'on');

    % EXTRACTION: Find the absolute peak heat and stress for this specific cycle
    history_MaxTemp(i) = max(out.Temp_smart.Data);
    history_MaxBSI(i) = max(out.BSI_smart.Data);

    % Calculate degradation and age the battery
    final_SOH = out.SOH_smart.Data(end);
    degradation = (var_SOH - final_SOH) * cycles_per_loop;

    var_SOH = var_SOH - degradation;
    var_Q = 50 * var_SOH; 
    var_R = 0.050 * (1 + 2 * (1 - var_SOH));

    % Log data
    history_Cycle(i) = i * cycles_per_loop;
    history_SOH(i) = var_SOH;
    history_Resistance(i) = var_R;

    fprintf('Cycle %d | Peak Temp: %.2f °C | Peak BSI: %.2f\n', history_Cycle(i), history_MaxTemp(i), history_MaxBSI(i));
end

% Bundle and save the new dataset directly to a CSV
Thermal_Dataset = table(history_Cycle, history_SOH, history_Resistance, history_MaxTemp, history_MaxBSI, ...
    'VariableNames', {'Cycle', 'SOH', 'Resistance', 'Max_Temp', 'Max_BSI'});
writetable(Thermal_Dataset, 'Predictive_Thermal_Dataset.csv');

fprintf('\nSuccess! Thermal Dataset saved as Predictive_Thermal_Dataset.csv\n');