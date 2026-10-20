function [Voltage,Current,SOC,Temperature,Rint,BSI,TargetC_rate,ChargeMode,SafetyStatus,xNext] = smart_battery_model(x,dt_s,sohInput)
%SMART_BATTERY_MODEL Simulink MATLAB Function block wrapper.
% State x is an explicit input; connect xNext through Unit Delay back to x.
p=parameters();
[y,xNext]=smart_battery_step(x,dt_s,p,sohInput);
Voltage=y(1); Current=y(2); SOC=y(3); Temperature=y(4);
Rint=y(5); BSI=y(6); TargetC_rate=y(7); ChargeMode=y(8); SafetyStatus=y(9);
end
