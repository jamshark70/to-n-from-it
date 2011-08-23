s.boot;

(
BP(\i2).free;
PR(\basicSynthChooser).chuck(BP(\i2), nil, (
	inChannels: 2,
	dir: thisProcess.nowExecutingPath.dirname,
	userprep: {
		~bufs = (~dir +/+ "samp/02*").pathMatch.collect { |path| Buffer.read(s, path) };
		Instr("busfx.cverb", { |bus, numChan, numDelays,
			cfreq, dwidth, dcenter,
			mix = 0.33, room = 0.5, damp = 0.5|
			var	sig = In.ar(bus, numChan),
			out = sig;
			numDelays.do {
				out = out + DelayL.ar(sig, 0.1,
					SinOsc.kr(cfreq * ExpRand(0.9, 1/0.9), Rand(0, pi), dwidth, dcenter)
				);
			};
			sig = FreeVerb2.ar(out[0], out[1], mix, room, damp);
			LeakDC.ar(sig)
		}, [
			#[0, 128, \lin, 1, 0], StaticSpec(1, 8, \lin, 1, 1), StaticSpec(1, 8, \lin, 1, 3),
			#[0.01, 1, \exp, 0, 0.1], #[0.001, 0.05, \exp, 0, 0.01], #[0.001, 0.05, \exp, 0, 0.01],
			#[0, 1], #[0, 1], #[0, 1]
		]);
		~chan.doWhenReady {
			~chorusVerb = ~chan.playfx(Instr("busfx.cverb"), [0, 2, 3, 0.079652607331209, 0.00940827137815, 0.02950861451756, 0.33000001311302, 0.7752999663353, 0.37079998850822]);
		};

	},
	userfree: { ~bufs.free },
	synth: Pwrand(#[grain, decim, reson, rcomb], #[5, 7, 1, 8].normalizeSum, inf),
	objects: { (
		grain: (
			def: ~makeDef.(\grain)
		),
		rcomb: (
			def: ~makeDef.(\grainrcomb, { |sig, fftsize = 128, wipe = 0.5|
				var	fft = FFT(LocalBuf(fftsize, 1), sig);
				fft = PV_RandComb(fft, wipe);
				IFFT(fft)
			}, true),
			args: [
				fftsize: 128,
				wipe: Pwhite(0.3, 0.8, inf),
				amp: Pkey(\amp) * Pkey(\wipe).linlin(0.3, 0.8, 1, 0.7)
			]
		),
		decim: (
			def: ~makeDef.(\graindecim, { |sig, resolution = 0.125, rateMul = 0.25, lpf = 19000|
				sig = Latch.ar(sig.round(resolution), Impulse.ar(SampleRate.ir * rateMul));
				LPF.ar(sig, lpf);
			}),
			args: [
				resolution: Pwhite(8, 48, inf).reciprocal,
				rateMul: Pwhite(4, 12, inf).reciprocal
			]
		),
		reson: (
			def: ~makeDef.(\grainreson, { |sig, ffreq = 2000, ringtime = 1, preamp = 1|
				Ringz.ar(sig, ffreq, ringtime, preamp).distort
			}, true),
			args: [
				ffreq: Pexprand(300, 1800, inf),
				ringtime: Pif(Pkey(\first), Pexprand(0.6, 1.0), Pexprand(0.2, 0.8)),
				preamp: Pwhite(1.0, 3.0, inf),
				amp: Pkey(\amp) * (-18.dbamp)
			]
		)
	) },
	makeDef: { |name, fxfunc, ringing = false|
		SynthDef(name, { |bufnum, rate = 1, start, time = 1,
			attack = 0.5, release = 0.5,
			amp = 0.1, pan = 0, out|
			var	sig = PlayBuf.ar(1, bufnum, rate, 1, start),
			eg = EnvGen.ar(Env(#[0, 1, 1, 0], [attack, max(0, 1.0 - attack - release), release], \sin),
				timeScale: time, doneAction: if(ringing) { 0 } { 2 });
			if(fxfunc.isFunction) {
				if(ringing) { sig = sig * eg };
				sig = SynthDef.wrap(fxfunc, prependArgs: [sig]);
			};
			if(ringing) {
				DetectSilence.ar(sig, doneAction: 2)
			};
			Out.ar(out, Pan2.ar(sig * if(ringing) { 1 } { eg }, pan, amp));
		})
	},
	makeOnePattern: { |time = 0.12, dur = 15, deltaMul(rrand(0.16, 0.3)), amp = 1, pan(1.0.rand2)|
		var wts = #[5, 5, 2, 1].normalizeSum;
		Pbind(
			\first, Pseq([true, Pn(false, inf)], 1),
			\synthKey, Pseq([\reson, BPStream(\synth)], 1),
			\instrument, Pfunc({ |ev|
				(ev[\synthKey] == \rest).if({ \rest },
					{ ~objects[ev[\synthKey]].tryPerform(\at, \name) ? \rest })
			}),
			\type, \grain,
			\bufnum, b.choose.bufnum,
			\start, ((~onsets.choose / ~bufs[0].duration) + Pwhite(-0.03, 0.03, inf)) * ~bufs[0].numFrames,
			\time, time,
			\delta, Pconst(dur, Pser(Array.fill(rrand(3, 6), { #[1, 2, 3, 4].wchoose(wts) }), inf) * deltaMul),
			\amp, amp,
			\pan, pan
		)
	},
	tenv: Env(#[0.12, 0.4, 0.12], #[25, 15], \sin),
	deltaMulEnv: Env(#[0.6, 0.4, 0.9], #[25, 15], #[1, 3]),
	waitEnv: Env(#[5.0, 3.0, 0.7, 3.0], #[5, 20, 15], #[lin, -3, -2.5]),
	ampEnv: { |dur| Env(#[1, 0.4], [dur], -5) },
	deltaMul: Pwhite(0.3, 0.5, inf),
	pan: Pwhite(0.2, 0.9, inf) * Pseq(#[-1, 1], inf, { 2.rand }),
	asPattern: {
		~deltaMulStream ?? { ~makeStreamForKey.(\deltaMul) };
		~panStream ?? { ~makeStreamForKey.(\pan) };
		Pspawner({ |sp|
			var	wait, dur, start = Ptime().asStream, totaldur = ~waitEnv.times.sum, now;
			while { (now = start.next) < totaldur } {
				wait = ~waitEnv.at(now);
				dur = max(7, wait * 4);
				sp.par(~makeOnePattern.(~tenv.at(now), dur, ~deltaMulEnv.at(now) * ~deltaMulStream.next, ~ampEnv.(dur), ~panStream.next));
				sp.wait(wait);
			};
		}).collect { |ev|
			if(ev[\synthKey].notNil and: { ev[\synthKey] != \rest }) {
				~getUserArgs.(ev);
			} { ev };
		}
	},
	// not big enough to warrant a separate data file
	onsets: #[ 1.0513292959206e-07, 0.1973732978903, 0.33669554897176, 0.7836877972685, 0.91139986821043, 1.1552138597571, 1.3583921463095, 1.4802990228735, 1.7299181491934, 1.9040708810888, 2.0317828924261, 2.2988174230658, 2.4961905748449, 2.6819534570776, 2.8735215932928, 3.065089729508, 3.4192004472815, 3.6339888841711, 4.2203035623633, 4.318989780625, 4.4060664445959, 4.5744142801367, 4.7833977014624, 5.1491184503637, 5.3522968561255, 5.4567885667883, 5.7064075738989, 5.9676366121374, 6.252086189469, 6.3623829156958, 6.4900951654516, 6.7222991258703, 6.8325958520971, 6.9312820703589, 7.0531893045508, 7.2795877725683, 7.4479356081091, 7.5292067796789, 7.6220884592138, 8.0284452707373, 8.1909876138769, 8.3070898325049, 8.4231910974585, 8.5741243631445, 8.7714967996679, 9.1314125330053, 9.5261593134009, 10.083448436936, 10.298236873826, 10.472389248093, 10.681372669419, 10.925187137803 ]
));

BP(\i2).alwaysReset = true;
0 => BP(\i2);
if(MixingBoard.at(0).w.isClosed) {
	MixingBoard(\x, nil, BP(\i2))
} {
	MixingBoard.at(0).add(BP(\i2))
};
)



(
if(t.notNil and: { t.isRunning }) { t.stop };
t = TLSequenceIterator([
	funcCmd: (
		setDoneSignal: {
			~doneSignal = OSCresponderNode(s.addr, '/n_go', e { |t, r, m|
				if(BP(\i2).chan.recProxy.notNil) {
					if(m[1] == BP(\i2).chan.recProxy.synth.nodeID) {
						~stop.();
					};
				};
			}).add;
		},
		func: {
			BP(\i2).chan.startRecord;
		},
		clearDoneSignal: { ~doneSignal.remove }
	),
	\cmdSync,
	0.1,
	bpCmd: (name: \i2),
	\sync,
	2,
	{ BP(\i2).chan.stopRecord; 0 }
]).play;
)

BP(\i2).chan.stopRecord;  // for emergencies