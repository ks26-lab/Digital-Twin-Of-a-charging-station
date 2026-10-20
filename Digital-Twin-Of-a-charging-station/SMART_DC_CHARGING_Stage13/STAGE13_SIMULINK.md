# Stage 13 — Simulink build instructions

These instructions match the provided files and nine signal outputs. MATLAB/Simulink labels can vary slightly by release.

## 1. Prepare MATLAB

Open this folder in MATLAB and set it as the Current Folder. In the Command Window run `p=parameters()` once to confirm the files are visible.

## 2. Create the model

1. In Simulink choose **Blank Model** and save as `SMART_DC_CHARGING_Stage13.slx` in this folder.
2. From Simulink → **User-Defined Functions**, add a **MATLAB Function** block. Rename it `smart_battery_model`.
3. Open the block, replace its contents with the full function shown below, then save/close the editor. The function name and file on the MATLAB path must be `smart_battery_model`.
4. Add a **Clock**, **Constant**, **Constant**, **Unit Delay**, **Mux**, and **Scope**.
5. Set the Constant blocks to `1` (sample time seconds) and `1` (SOH fraction). Set Unit Delay initial condition to `[0.20; 25; 0; 1]`, sample time to `1` if that parameter is shown.

## 3. Make state feedback

The MATLAB Function inputs are `x`, `dt_s`, `sohInput`. Its outputs are the nine named signals followed by `xNext` (the tenth output).

- Connect Unit Delay output to `x`.
- Connect the `dt_s` Constant (1) to `dt_s`.
- Connect the SOH Constant (1) to `sohInput`.
- Connect output `xNext` back to Unit Delay input.
- The Clock block is optional. It may be connected to a Display block, but is not required by the battery model.

This explicit Unit Delay feedback avoids persistent variables. It also gives every simulation run a known initial state.

## 4. Plot the nine signals

Set Mux **Number of inputs** to `9`. Connect the MATLAB Function outputs to Mux inputs in this exact order:

1. Voltage
2. Current
3. SOC
4. Temperature
5. Rint
6. BSI
7. TargetC_rate
8. ChargeMode
9. SafetyStatus

Connect Mux output to Scope. Scope has **one input port** because Mux creates one vector. In Scope settings set **Input processing** to **Elements as channels** and **Display grid** to `[9,1]` (or `[3,3]` if nine vertical axes are cramped). Do not change Scope input ports to nine.

## 5. Paste-ready MATLAB Function block code

```matlab
function [Voltage,Current,SOC,Temperature,Rint,BSI,TargetC_rate,ChargeMode,SafetyStatus,xNext] = smart_battery_model(x,dt_s,sohInput)
% x = [SOC; temperature_C; previous_current_A; SOH]
p.Q_Ah=2.5; p.Vmin_V=3.0; p.Vmax_V=4.2; p.Imax_A=2.5;
p.Rint_Ohm=0.08; p.Rth_K_per_W=3.0; p.Cth_J_per_K=500;
p.Tamb_C=25; p.Twarn_C=45; p.Tstop_C=55;
p.SOCmin=0.02; p.SOCmax=0.98; p.CC_C_rate=0.5;
p.CV_taper_A=0.125;
soc=min(max(x(1),0),1); T=x(2); soh=min(max(sohInput,0),1);
ocv=3.0+1.2*soc; v=ocv;
crate=p.CC_C_rate;
if soc>=0.80, crate=min(crate,0.30); end
if T>=p.Twarn_C-5, crate=min(crate,0.20); end
if soh<0.80, crate=min(crate,0.25); end
if soc>=p.SOCmax-0.01 || T>=p.Tstop_C, crate=0; end
if soc>=p.SOCmax || v>=p.Vmax_V || crate<=0
    i=0; mode=0;
elseif v<p.Vmax_V-0.10 && soc<0.80
    i=crate*p.Q_Ah; mode=1;
else
    i=min(crate*p.Q_Ah,max(p.CV_taper_A,p.Imax_A*max(p.Vmax_V-v,0)/0.10)); mode=2;
end
i=min(max(i,0),p.Imax_A); v=ocv+i*p.Rint_Ohm;
status=0;
if T>=p.Tstop_C || soc>=p.SOCmax || v>=p.Vmax_V+0.05
    status=2;
elseif T>=p.Twarn_C || soc>=p.SOCmax-0.03 || v>=p.Vmax_V-0.05
    status=1;
end
if status==2 || (status==1 && T>=p.Tstop_C-2), i=0; mode=0; v=ocv; end
socNext=min(max(soc+i*dt_s/(3600*p.Q_Ah),0),1);
heat=i*i*p.Rint_Ohm;
Tnext=T+dt_s*(heat-(T-p.Tamb_C)/p.Rth_K_per_W)/p.Cth_J_per_K;
if abs(i)<1e-6, r=p.Rint_Ohm; else, r=max(abs(v-ocv)/abs(i),1e-4); end
tRisk=min(max((T-p.Tamb_C)/(p.Tstop_C-p.Tamb_C),0),1);
rRisk=min(max((r/p.Rint_Ohm-1)/2,0),1);
socRisk=double(soc<p.SOCmin || soc>p.SOCmax);
bsi=100*min(max(0.55*tRisk+0.30*rRisk+0.15*socRisk,0),1);
Voltage=v; Current=i; SOC=soc; Temperature=T; Rint=r; BSI=bsi;
TargetC_rate=crate; ChargeMode=mode; SafetyStatus=status;
xNext=[socNext;Tnext;i;soh];
end
```

Set model **Stop Time** to `1800`, solver to a fixed-step discrete solver, and fixed step size to `1`. Run. The initial SOC is 0.20. Outputs are illustrative and the simplified controller may show CC/CV mode transitions based on the toy OCV equation.

## Troubleshooting

- Missing function or undefined `parameters`: confirm this project folder is the Current Folder or on the MATLAB path.
- State dimension error: Unit Delay initial condition must have exactly four elements in the order `[SOC; temperature_C; previous_current_A; SOH]`.
- Only a few Scope traces: confirm all nine scalar outputs are wired to a 9-input Mux, then Mux to Scope; set Input processing to Elements as channels.
- Scope ports: the Scope receives one vector, so its input port count remains 1.
