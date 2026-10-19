function r = rint_estimator(v_terminal_V, ocv_V, current_A, fallback_Ohm)
%RINT_ESTIMATOR Estimate |V-OCV|/|I|; fallback at near-zero current.
if abs(current_A) < 1e-6
    r = fallback_Ohm;
else
    r = max(abs(v_terminal_V-ocv_V)/abs(current_A),1e-4);
end
end
