function soc_next = soc_estimator(soc, current_A, dt_s, p)
%SOC_ESTIMATOR Coulomb counting; positive current charges the cell.
soc_next = min(max(soc + current_A*dt_s/(3600*p.Q_Ah),0),1);
end
