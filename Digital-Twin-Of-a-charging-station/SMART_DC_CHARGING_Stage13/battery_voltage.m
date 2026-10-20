function v = battery_voltage(soc, current_A, p)
%BATTERY_VOLTAGE Simplified OCV minus ohmic drop, charging current positive.
soc = min(max(soc,0),1);
ocv = 3.0 + 1.2*soc;
v = ocv + current_A*p.Rint_Ohm;
end
