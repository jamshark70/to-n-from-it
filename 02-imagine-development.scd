~dir = thisProcess.nowExecutingPath.dirname;

s.boot;

b.free;
b = (~dir +/+ "samp/02*").pathMatch.collect { |path| Buffer.read(s, path) };

m = MixerChannel(\test, s, 2, 2, level: -25.dbamp);
MixingBoard(\x, nil, m);


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
	if(msg[1] == a.nodeID) {
		OSCdef(\tr.debug("removing")).free;
		OSCdef(\n_end).free;
	};
}, '/n_end', s.addr);

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