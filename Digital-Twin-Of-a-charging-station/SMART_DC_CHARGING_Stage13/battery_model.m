function [v_terminal_V, heat_W] = battery_model(soc, current_A, p)
%BATTERY_MODEL Single-resistance equivalent circuit and Joule heating.
v_terminal_V = battery_voltage(soc,current_A,p);
heat_W = current_A.^2 .* p.Rint_Ohm;
end
