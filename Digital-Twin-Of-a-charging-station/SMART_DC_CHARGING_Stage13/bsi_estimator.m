function bsi = bsi_estimator(T_C, soc, rint_Ohm, p)
%BSI_ESTIMATOR Heuristic 0-100 risk score; not a validated safety index.
tRisk = min(max((T_C-p.Tamb_C)/(p.Tstop_C-p.Tamb_C),0),1);
rRisk = min(max((rint_Ohm/p.Rint_Ohm-1)/2,0),1);
socRisk = double(soc < p.SOCmin || soc > p.SOCmax);
bsi = 100*min(max(0.55*tRisk + 0.30*rRisk + 0.15*socRisk,0),1);
end
