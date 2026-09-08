LIBNAME SERIES 'C:\Users\Isaias\Documents\SAS Clases'; 
 
proc import  
	datafile = 'C:\Users\Isaias\Documents\TFM\processed\GTA_MARQUES_DE_VADILLO_1_por_accidentes.csv' 
    out=SERIES.MARQUES 
    dbms=csv 
	replace; 
run; 
 
 
/* GENERACION DE FECHA */ 
 
data SERIES.MARQUES; 
set SERIES.MARQUES; 
fecha = intnx('month', '01jan2019'd, _n_-1); 
	format fecha DATE.; 
RUN; 
 
 
/* DELIMITACION DE FECHA - HASTA 06-2025 */ 

data SERIES.MARQUES; 
    set SERIES.MARQUES; 
    where fecha < '01jul2025'd; 
run; 
 
 
/* GRAFICO DE SERIES ORIGINALES */ 

proc sgplot data = SERIES.MARQUES;  
	series x = fecha y = freq_multas; 
	series x = fecha y = freq_accidentes / y2axis; 
run; 
 
 
/* GRAFICOS DE SERIES DESCOMPUESTAS */ 

proc timeseries data = SERIES.MARQUES PLOTS = (TC SC SA IC) 
PRINT = (SEASONS DECOMP); 
	id fecha interval = month; 
	var freq_multas freq_accidentes; 
run; 
 
 
/* SUAVIZADO WINTERS ADITIVO - ACCIDENTES */ 

proc esm data = SERIES.MARQUES back = 6 lead = 6 
         print=(ALL) plot=(ALL) 
         outfor = series.PRED_HW 
         nooutall; 
    id fecha interval = month; 
    forecast freq_accidentes / model = addwinters; 
run; 
 
 
/* DIVISION TRAIN TEST (ULTIMOS 6 MESES) */ 

data series.MARQUES_TRAIN series.MARQUES_TEST; 
	set series.MARQUES; 
	if fecha<'01jan25'd then output series.MARQUES_TRAIN; 
		else output series.MARQUES_TEST;  
run; 
 
 
/* ARIMA MULTAS */ 

proc arima data = series.MARQUES_TRAIN; 
	identify var = freq_multas nlag=24;  
run; 
 
proc arima data = series.MARQUES_TRAIN; 
	identify var = freq_multas(1) nlag=24;  
run; 
 
proc arima data = series.MARQUES_TRAIN; 
	identify var = freq_multas(1) nlag=24; 
	estimate p=2; 
run; 
 
proc arima data = series.MARQUES_TRAIN; 
	identify var = freq_multas(1) nlag=24;  
	estimate q=2; 
run; 
 
proc arima data = series.MARQUES_TRAIN; 
	identify var = freq_multas(1) nlag=24;  
	estimate p=4; 
run; 
 
proc arima data = series.MARQUES_TRAIN; 
	identify var = freq_multas(1) nlag=24; /* MODELO ELEGIDO */
	estimate p=3; 
run; 
 
proc arima data = series.MARQUES_TRAIN; 
	identify var = freq_multas(1) nlag=24; 
	estimate q=3; 
run; 
 
 
/* ARIMA ACCIDENTES */ 

proc arima data = series.MARQUES_TRAIN; 
	identify var = freq_accidentes nlag=24; 
	estimate method=ml;/* SERIE ORIGINAL - MODELO ELEGIDO */ 
run; 
 
/*
proc arima data = series.MARQUES_TRAIN; 
	identify var = freq_accidentes(1) nlag=24;  
run; 
 
proc arima data = series.MARQUES_TRAIN; 
	identify var = freq_accidentes(1) nlag=24;  
	estimate p=1; 
run; 
 
proc arima data = series.MARQUES_TRAIN; 
	identify var = freq_accidentes(1) nlag=24;  
	estimate q=1; 
run; 
*/
 
/* AUTOREG */ 
 
/* AJUSTE TRAIN */ 

proc autoreg data=series.MARQUES_TRAIN; 
	model freq_accidentes=freq_multas / nlag=6 backstep method=ml; 
run; 
 
 
/* DATASET COMBINADO: TRAIN CON ACCIDENTES REAL,
   TEST CON ACCIDENTES EN MISSING */ 

data series.MARQUES_FORECAST; 
    set series.MARQUES_TRAIN 
        series.MARQUES_TEST(in=intest); 
    if intest then freq_accidentes =.; 
    /* freq_multas se mantiene con su valor real,
       porque es la variable exógena conocida */ 
run; 
 
 
proc autoreg data=series.MARQUES_FORECAST
             PLOTS (UNPACK) = ALL; 
    model freq_accidentes = freq_multas
        / nlag=6 backstep method=ml dw=6 dwprob; 
    output out=p p=yhat lcl=lcl ucl=ucl; 
run; 
 
 
data series.COMPARA_AUTOREG; 
    merge p(keep=fecha yhat lcl ucl) 
          series.MARQUES_TEST(
              keep=fecha freq_accidentes
              rename=(freq_accidentes=real)
          ); 
    by fecha; 
    where fecha >= '01jan2025'd; 
    error = real - yhat; 
    error_pct = abs(error) / real * 100; 
run; 
 
 
title 'Predicciones para el modelo de regresión dinámica'; 

proc sgplot data=series.COMPARA_AUTOREG; 
	band x=fecha upper=ucl lower=lcl; 
	scatter x=fecha y=real; 
	series x=fecha y=yhat; 
run; 

title; 
 
 
/* ARIMA CORR */ 

proc arima data=series.MARQUES_TRAIN; 
	identify var=freq_accidentes
             crosscorr=(freq_multas(1)); 
	estimate 
             input=(freq_multas)
             method=ml
             plot; 
run; 
 
 
/* ARIMA CORR - CON PREDICCION */ 

proc arima data=series.MARQUES_FORECAST; 
    identify var=freq_accidentes
             crosscorr=(freq_multas(1)); 
    estimate 
             input=(freq_multas)
             method=ml
             plot; 
    forecast lead=6
             id=fecha
             interval=month
             out=series.PRED_ARIMAX; 
run; 
 
 
/* MAPE DE AJUSTE ARIMAX - IN SAMPLE */ 

proc arima data=series.MARQUES_TRAIN; 
    identify var=freq_accidentes
             crosscorr=(freq_multas(1)); 

    estimate 
             input=(freq_multas)
             method=ml; 

    forecast id=fecha
             interval=month
             out=series.ARIMAX_AJUSTE; 
run; 
 
 
data series.COMPARA_ARIMAX; 
    merge series.PRED_ARIMAX(
              keep=fecha forecast l95 u95
          ) 
          series.MARQUES_TEST(
              keep=fecha freq_accidentes
              rename=(freq_accidentes=real)
          ); 
    by fecha; 
    where fecha >= '01jan2025'd; 
    error = real - forecast; 
    error_pct = abs(error) / real * 100; 
run; 
 
 
title 'Pronóstico ARIMAX de accidentes con multas como variable exógena'; 

proc sgplot data=series.COMPARA_ARIMAX; 
    band x=fecha upper=u95 lower=l95; 
    scatter x=fecha y=real; 
    series x=fecha y=forecast; 
run; 

title; 
 
 
title 'MAPE del modelo AUTOREG en test (out-of-sample)'; 
 
proc sql; 
    create table series.COMPARA_AUTOREG as 
    select fecha, yhat, lcl, ucl, real, error, error_pct 
    from series.COMPARA_AUTOREG; 
quit; 
 
proc print data=series.COMPARA_AUTOREG; 
run; 
 
proc means data=series.COMPARA_AUTOREG mean; 
    var error_pct; 
run; 

title; 
 
 
title 'MAPE del modelo ARIMAX (regresión dinámica) en test';	 
 
proc print data=series.COMPARA_ARIMAX; 
run; 
 
proc means data=series.COMPARA_ARIMAX mean; 
    var error_pct; 
run; 

title; 
 
 
data series.COMPARA_VISUAL; 
    merge
        series.MARQUES_TEST(
            keep=fecha freq_accidentes
            rename=(freq_accidentes=real)
        )
        p(
            keep=fecha yhat
            rename=(yhat=pred_autoreg)
        )
        series.PRED_ARIMAX(
            keep=fecha forecast
            rename=(forecast=pred_arimax)
        )
        series.PRED_HW(
            keep=fecha PREDICT
            rename=(PREDICT=pred_hw)
        );

    by fecha; 
    where fecha >= '01jan2025'd; 
run; 
 
 
title 'Comparación de pronósticos: Holt-Winters, AUTOREG y ARIMAX'; 

proc sgplot data=series.COMPARA_VISUAL; 

    series x=fecha y=real
        / lineattrs=(color=black thickness=2)
          markers
          legendlabel='Real';

    series x=fecha y=pred_hw
        / lineattrs=(color=green thickness=2)
          legendlabel='Holt-Winters';

    series x=fecha y=pred_autoreg
        / lineattrs=(color=blue thickness=2)
          legendlabel='AUTOREG';

    series x=fecha y=pred_arimax
        / lineattrs=(color=red thickness=2)
          legendlabel='ARIMAX';

    xaxis type=time
          interval=month
          valuesformat=monyy7.;

    yaxis label='Frecuencia de accidentes';

    keylegend / position=bottom;
run; 

title;
