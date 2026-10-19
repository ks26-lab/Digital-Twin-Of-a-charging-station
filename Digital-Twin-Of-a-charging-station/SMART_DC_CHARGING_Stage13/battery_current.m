function i = battery_current(v_terminal_V, soc, p)
%BATTERY_CURRENT Current implied by terminal voltage and simple OCV model.
soc = min(max(soc,0),1);
ocv = 3.0 + 1.2*soc;
i = (v_terminal_V-ocv)/p.Rint_Ohm;
end
