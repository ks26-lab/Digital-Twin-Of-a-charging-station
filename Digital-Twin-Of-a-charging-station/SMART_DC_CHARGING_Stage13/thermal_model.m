function Tnext_C = thermal_model(T_C, current_A, dt_s, p)
%THERMAL_MODEL Lumped thermal Euler step; I^2R heat and ambient cooling.
heat_W = current_A.^2*p.Rint_Ohm;
dTdt = (heat_W - (T_C-p.Tamb_C)/p.Rth_K_per_W)/p.Cth_J_per_K;
Tnext_C = T_C + dt_s*dTdt;
end
