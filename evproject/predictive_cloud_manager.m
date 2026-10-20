% --- PHASE 18-20: PREDICTIVE ADAPTIVE CHARGING MANAGER ---
fprintf('Initiating Cloud-to-Vehicle Predictive Charging Protocol...\n');

% 1. Define the vehicle's current state (An aged battery pulling into a station)
current_cycle = 980;
var_SOH = 0.78;  % 85% Health
var_Q = 50 * var_SOH; 
var_R = 0.050 * (1 + 2 * (1 - var_SOH));

% 2. AI PREDICTION: Forecast the peak stress of the upcoming charge
% (Using the weights calculated in train_thermal_ai.m)
X_current = [1, var_SOH, var_R, log10(current_cycle)];
predicted_peak_Temp = X_current * weights_Temp;
predicted_peak_BSI = X_current * weights_BSI;

fprintf('AI FORECAST | Predicted Peak Temp: %.2f °C | Predicted Peak BSI: %.2f\n', predicted_peak_Temp, predicted_peak_BSI);

% 3. MULTI-OBJECTIVE OPTIMIZATION (The Decision Matrix)
% The AI proactively throttles the charger to keep BSI strictly below 52.0
if predicted_peak_BSI >= 54.0
    var_C_Max = 0.9; % Aggressive throttling for very old batteries
    fprintf('AI DECISION: High stress predicted. Throttling Max C-Rate to 0.9C\n');
elseif predicted_peak_BSI >= 52.0
    var_C_Max = 1.2; % Moderate throttling
    fprintf('AI DECISION: Elevated stress predicted. Throttling Max C-Rate to 1.2C\n');
else
    var_C_Max = 1.5; % Full speed for healthy batteries
    fprintf('AI DECISION: Battery healthy. Authorizing full 1.5C Fast Charge\n');
end

% 4. Push parameters to the vehicle (Simulink Workspace)
assignin('base', 'var_SOH', var_SOH);
assignin('base', 'var_Q', var_Q);
assignin('base', 'var_R', var_R);
assignin('base', 'var_C_Max', var_C_Max);

% 5. Execute the optimized charge
fprintf('Executing Smart Charge...\n');
out = sim('Smart_DC_Fast_Charging', 'ReturnWorkspaceOutputs', 'on');

% 6. Validate the AI's success
actual_peak_Temp = max(out.Temp_smart.Data);
actual_peak_BSI = max(out.BSI_smart.Data);
fprintf('CHARGE COMPLETE | Actual Peak Temp: %.2f °C | Actual Peak BSI: %.2f\n', actual_peak_Temp, actual_peak_BSI);

% 7. Visualization: Proving the optimization worked
figure('Name', 'Predictive Charge Optimization', 'Color', 'w');
subplot(2,1,1);
plot(out.tout, out.BSI_smart.Data, 'g', 'LineWidth', 2);
yline(52.0, '--r', 'AI Safety Target (52.0)', 'LineWidth', 1.5);
title(sprintf('Cycle %d: Proactive BSI Management (Max C-Rate = %.1fC)', current_cycle, var_C_Max));
ylabel('Battery Stress Index'); grid on;

subplot(2,1,2);
plot(out.tout, out.Temp_smart.Data, 'r', 'LineWidth', 2);
title('Temperature Profile During Optimized Charge');
xlabel('Time (seconds)'); ylabel('Temperature (°C)'); grid on;