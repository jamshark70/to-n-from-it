~dir = thisProcess.nowExecutingPath.dirname;

s.waitForBoot {
	b.free;
	b = (~dir +/+ "samp/02*").pathMatch.collect { |path| Buffer.read(s, path) };
	m = MixerChannel(\test, s, 2, 2, level: -25.dbamp);
	MixingBoard(\x, nil, m);
};

ChuckableBrowser.newWindow;

MT(1).gui;


b[0].duration  // c. 11 sec


// where are note onsets?
a = m.play {
	var sig = PlayBuf.ar(1, b[0], doneAction: 2),
		fft = FFT(LocalBuf(512, 1), sig),
		trig = Onsets.kr(fft, threshold: 0.5, odftype: \rcomplex/*, relaxtime: 1, floor: 0.1, mingap: 10, medianspan: 11, whtype: 1, rawodf: 0*/),
		time = Line.kr(0, 20, 20);
	time.poll(trig, trigid: 1);
	sig ! 2
};
l = List.new;
OSCdef(\tr, { |msg| l.add(msg[3] - (256/44100)) }, '/tr', s.addr);
OSCdef(\n_end, { |msg|
		OSCdef(\tr.debug("removing")).free;
		OSCdef(\n_end).free;
}, ['/n_end', a.nodeID], s.addr);


a.free;

l.differentiate  // no obvious pattern

p = m.play(Pbind(
	\instrument, \bufGrainPan,
	\bufnum, b[0],
	\start, Pseq(l) * b[0].sampleRate - (256/44100),
	\time, 0.1,
	\dur, 0.25,
	\amp, 1
));

p.stop;


a = m.play {
	var	trig = Impulse.kr(15),
		dur = Line.kr(5, 0.1, 30) / 15,
		pos = TChoose.kr(trig, l) / b[0].duration;
	GrainBuf.ar(2, trig, dur, b, rate: 1, pos: pos, pan: #[-1, 1], envbufnum: -1);
};

a.trace;

a.free;


// nice, but some onsets are really offensive
a = m.play {
	var	trig = Impulse.kr(15),
		dur = 4/15, // Line.kr(5, 0.1, 30) / 15,
		basePos = Demand.kr(trig ! 2, 0, { Dstutter(Dwhite(5, 45, inf), Dxrand(l, inf)) } ! 2),
		pos = SinOsc.kr(0.1, 0, 0.01, basePos / b[0].duration);
	GrainBuf.ar(2, trig, dur, b, rate: 1, pos: pos, pan: #[-1, 1], envbufnum: -1);
};

a.trace;

a.free;


// maybe sounds are smoother in between the onsets (i.e., *avoid* onsets)
// accel/ritard is WAY too obvious...
a = m.play {
	var	tfreqs = {
			EnvGen.kr(Env(
				[rrand(0.8, 1.2), rrand(14.0, 16.0), rrand(0.4, 0.6)],
				[15, 15],
				\exp
			))
		} ! 2,
		trig = Impulse.kr(tfreqs * LFNoise1.kr(8 ! 2).exprange(0.8, 1.25)),
		dur = 4 / 15, // Line.kr(5, 0.1, 30) / 15,
		// funny hack to avoid breaking the 'var' list
		onsets = {
			var x = List.new;
			l.doAdjacentPairs { |a, b| x.add(a.blend(b, 0.5)) };
			x
		}.value,
		basePos = Demand.kr(trig, 0, {
			Dstutter(Dwhite(5, 45, inf), Dxrand(onsets, inf))
		} ! 2),
		width = Line.kr(0, 0.02, 30),
		pos = SinOsc.kr(1, 0, width, basePos / b[0].duration);
	GrainBuf.ar(2, trig, dur, b, rate: 1, pos: pos, pan: #[-1, 1], envbufnum: -1).sum;
};

a.trace;

a.free;


// need rhythm -- switch to patterns
SynthDef(\grain, { |bufnum, rate = 1, start, time = 1,
	attack = 0.5, release = 0.5,
	amp = 0.1, pan = 0, out|
	var	sig = PlayBuf.ar(1, bufnum, rate, 1, start),
		eg = EnvGen.ar(Env(#[0, 1, 1, 0], [attack, max(0, 1.0 - attack - release), release], \sin),
			timeScale: time, doneAction: 2);
	Out.ar(out, Pan2.ar(sig * eg, pan, amp));
}).add;

// try to replicate sliding grain thingy in a pattern
// more or less
p = m.play(Pbind(
	\instrument, \grain,
	\type, \grain,
	\bufnum, b.collect(_.bufnum),
	\start, ((l.choose / b[0].duration) + (sin(Ptime() * (0.25 * 2pi)) * 0.02)) * b[0].numFrames,
	\time, 4/15,
	\delta, 1/15,
	\amp, 1,
	\pan, #[-1, 1]
));

p.stop;



// try to replicate sliding grain thingy in a pattern
// more or less
p = m.play(Pbind(
	\instrument, \grain,
	\type, \grain,
	\bufnum, b.collect(_.bufnum),
	// \start, ((l.choose / b[0].duration) + (sin(Ptime() * (0.25 * 2pi)) * 0.02)) * b[0].numFrames,
	\start, ((l.choose / b[0].duration) + Pwhite(-0.03, 0.03, inf)) * b[0].numFrames,
	\time, 0.12,
	// \delta, Pwrand(#[1, 2, 3, 4], #[5, 5, 2, 1].normalizeSum, rrand(8, 20)) * rrand(0.16, 0.3),
	\delta, {
		var wts = #[5, 5, 2, 1].normalizeSum;
		Pser(Array.fill(rrand(3, 6), { #[1, 2, 3, 4].wchoose(wts) }), rrand(8, 20)) * rrand(0.16, 0.3)
	}.value,
	\amp, 1,
	\pan, #[-1, 1]
));

p.stop;


q = Pbind(
	\instrument, \grain,
	\type, \grain,
	\bufnum, Plazy({ b.choose.bufnum.loop }),
	\start, Plazy({
		loop(((l.choose / b[0].duration) + Pwhite(-0.03, 0.03, inf)) * b[0].numFrames)
	}),
	\time, 0.12,
	// \delta, Pwrand(#[1, 2, 3, 4], #[5, 5, 2, 1].normalizeSum, rrand(8, 20)) * rrand(0.16, 0.3),
	\delta, Plazy({
		var wts = #[5, 5, 2, 1].normalizeSum;
		Pconst(15, Pser(Array.fill(rrand(3, 6), { #[1, 2, 3, 4].wchoose(wts) }), inf) * rrand(0.16, 0.3))
	}),
	\amp, 1,
	\pan, Plazy({ 1.0.rand2.loop })
);

m.play(q);

q = { |time = 0.12, dur = 15, deltaMul(rrand(0.16, 0.3)), amp = 1, pan(1.0.rand2)|
	var wts = #[5, 5, 2, 1].normalizeSum;
	Pbind(
		\instrument, \grain,
		\type, \grain,
		\bufnum, b.choose.bufnum,
		\start, ((l.choose / b[0].duration) + Pwhite(-0.03, 0.03, inf)) * b[0].numFrames,
		\time, time,
		\delta, Pconst(dur, Pser(Array.fill(rrand(3, 6), { #[1, 2, 3, 4].wchoose(wts) }), inf) * deltaMul),
		\amp, amp,
		\pan, pan
	)
};

// still tuning dur - takes too long to build
// also needs fx in the synth, maybe multiple synthdefs
p = m.play(Pspawner({ |sp|
	var	tenv = Env(#[0.12, 0.25, 0.12], #[9.5, 9.5], \sin),
		deltaMulEnv = Env(#[1.0, 0.1, 1.0], #[9.5, 9.5], 4),
		waitEnv = Env(#[3.0, 0.3, 3.0], 9.5 ! 2, -2),
		dur;
	20.do { |wt|
		dur = waitEnv.at(wt);
		sp.par(q.value(tenv.at(wt), max(7, dur * 4), deltaMulEnv.at(wt) * rrand(0.3, 0.5)));
		sp.wait(dur.debug("waiting"));
	};
}));
u.remove;
u = SimpleController(p).put(\stopped, { "done".postln; u.remove });

q.listArgs

p.stop;


// thinking of multiple synths for fx: PR(\basicSynthChooser)
(
BP(\i2).free;
PR(\basicSynthChooser).chuck(BP(\i2), nil, (
	inChannels: 2,
	dir: thisProcess.nowExecutingPath.dirname,
	userprep: {
		~bufs = (~dir +/+ "samp/02*").pathMatch.collect { |path| Buffer.read(s, path) };
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
				ringtime: Pif(Pkey(\first), Pwhite(2.0, 5.0, inf), Pexprand(0.2, 0.8, inf)),
				preamp: Pwhite(1.0, 3.0, inf),
				amp: Pkey(\amp) * (-12.dbamp)
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
	tenv: Env(#[0.12, 0.25, 0.12], #[9.5, 9.5], \sin),
	deltaMulEnv: Env(#[1.0, 0.1, 1.0], #[9.5, 9.5], #[1, 3]),
	waitEnv: Env(#[3.0, 0.3, 3.0], 9.5 ! 2, -2),
	ampEnv: { |dur| Env(#[1, 0.1], [dur], \exp) },
	deltaMul: Pwhite(0.3, 0.5, inf),
	asPattern: {
		~deltaMulStream ?? { ~makeStreamForKey.(\deltaMul) };
		Pspawner({ |sp|
			var	wait, dur, start = Ptime().asStream, totaldur = ~waitEnv.times.sum, now;
			while { (now = start.next) < totaldur } {
				wait = ~waitEnv.at(now);
				dur = max(7, wait * 4);
				sp.par(~makeOnePattern.(~tenv.at(now), dur, ~deltaMulEnv.at(now) * ~deltaMulStream.next, ~ampEnv.(dur)));
				sp.wait(wait.debug("waiting"));
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
if(MixingBoard.at(0).w.isClosed.not) { MixingBoard.at(0).add(BP(\i2)) };
if(MT.exists(MIDIChannelIndex(0, 1))) { BP(\i2) => MT(1) };
)

BP(\i2).resonamp = Pkey(\amp) * (-18.dbamp);
BP(\i2).synth = Pwrand(#[grain, decim, reson, rcomb], #[5, 5, 1, 5].normalizeSum, inf);

BP(\i2).ampEnv = { |dur| Env(#[1, 0.4], [dur], -5) };

BP(\i2).rcombamp = Pkey(\amp) * Pkey(\wipe).linlin(0.3, 0.8, 1, 0.7);

z = BP(\i2);

x = #[15, 22];
z.tenv = Env(#[0.12, 0.25, 0.12], x, \sin);
z.deltaMulEnv = Env(#[0.6, 0.4, 0.9], x, #[1, 3]);
z.waitEnv = Env(#[5.0, 3.0, 0.7, 3.0], #[5, 12, 20], #[lin, -3, -2.5]);

z.resonamp.postcs
z.resonamp = Pkey(\amp) * (-18.dbamp);
z.resonringtime.postcs
z.resonringtime = Pif(Pkey(\first), Pexprand(1.0, 1.4).trace(prefix: "long: "), Pexprand(0.2, 0.8));

z.listVars
z.waitEnv.postcs
z.waitEnv = Env(#[3.0, 0.3, 3.0], 9.5 ! 2, -2),

d = BP(\i2).makeDef(\grainreson, { |sig, ffreq = 2000, ringtime = 1, preamp = 1|
	Ringz.ar(sig, ffreq, ringtime, preamp).distort
}, true).add;

m.play((
	instrument: \grainreson,
	bufnum: z.bufs[0],
	start: z.onsets.choose * z.bufs[0].sampleRate,
	time: 0.2,
	amp: 1,
	ffreq: exprand(300, 1800),
	ringtime: 0.5,
	preamp: 1
));

d = BP(\i2).makeDef(\graindecim, { |sig, resolution = 0.125, rateMul = 0.25, lpf = 19000|
	sig = Latch.ar(sig.round(resolution), Impulse.ar(SampleRate.ir * rateMul));
	LPF.ar(sig, lpf);
}).add;

m.play((
	instrument: \graindecim,
	bufnum: z.bufs[0],
	start: z.onsets.choose * z.bufs[0].sampleRate,
	time: 0.2,
	amp: 1,
	resolution: 1/32,
	rateMul: 1/32,
	attack: 0.05,
	decay: 0.95
));

d = BP(\i2).makeDef(\grainrcomb, { |sig, fftsize = 128, wipe = 0.5|
	var	fft = FFT(LocalBuf(fftsize, 1), sig);
	fft = PV_RandComb(fft, wipe);
	IFFT(fft)
}, true).add;

m.play((
	instrument: \grainrcomb,
	bufnum: z.bufs[0],
	start: z.onsets.choose * z.bufs[0].sampleRate,
	time: 0.2,
	amp: 1,
	fftsize: 128,
	wipe: rrand(0.3, 0.8),
	attack: 0.05,
	decay: 0.95
));

