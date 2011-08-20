~dir = thisProcess.nowExecutingPath.dirname;

s.boot;

b.free;
b = Buffer.read(s, ~dir +/+ "samp/01-arpeg2.aiff");
b.plot;

a = {
	var	sig = PlayBuf.ar(1, b, loop: 0)
			* EnvGen.kr(Env.linen(0.002, b.duration - 0.05, 0.048), doneAction: 2);
	RecordBuf.ar(sig, b, loop: 0);
	0
}.play;

m = MixerChannel(\test, s, 1, 2);
MixingBoard(\x, nil, m);

// sounds right
m.play(\bufGrain, [time: b.duration, bufnum: b]);

// use as kernel for PartConv
~fftsize = 512;
~kernel.free;
~kernel = Buffer.alloc(s, PartConv.calcBufSize(~fftsize, b));
~kernel.preparePartConv(b, ~fftsize);

a = m.play {
	var	sig = In.ar(8, 1);
	Limiter.ar(PartConv.ar(sig, ~fftsize, ~kernel))
};

a.free;

c = Buffer.read(s, ~dir +/+ "samp/01-slide.aiff");

~conv = m.playfx { |outbus|
	var	sig = In.ar(outbus, 1);
	Limiter.ar(PartConv.ar(sig, ~fftsize, ~kernel))
};

p = m.play(Pbind(
	\instrument, \bufGrain,
	\bufnum, c,
	\time, c.duration,
	\dur, 0.5
));

p.stop;

p = m.play((
	instrument: \bufGrain,
	bufnum: c,
	time: c.duration,
	dur: 0.5
));

~conv.run(false);
~conv.run(true);

SynthDef(\saw, { |freq = 440, amp = 0.1, rq = 1, detuneR = 1.003, attack = 0.1, release = 0.5, gate = 1, timeScale = 1, out|
	var	sig = Saw.ar(freq * [1, detuneR], amp).sum,
		ffreqenv = NamedControl.kr(\ffreqenv,
			(0 ! 32).overWrite(Env(#[2000, 2000], #[1]).asArray)
		),
	ffreq = EnvGen.kr(ffreqenv, timeScale: timeScale);
	sig = RLPF.ar(sig, ffreq, rq);
	sig = sig * EnvGen.kr(Env.asr(attack, 1, release), gate, doneAction: 2);
	Out.ar(out, sig);
}).add;

m.play((
	instrument: \saw,
	root: 2,
	degree: #[0, 2, 4],
	sustain: 6,
	timeScale: 6,
	ffreqenv: [Env(#[180, 15000, 180], #[0.25, 0.75], \exp)],
	rq: 0.05
));

p = m.play(x = PbindProxy(*[
	instrument: \saw,
	root: 2,
	degree: Pwrand([
		-14, -10, -9, -6, -5, -3, Pwhite(-1, 11, 1)
	], #[1, 1, 1, 2, 2, 2, 10].normalizeSum, inf),
	attack: 0.01,
	release: 1,
	sustain: Pwhite(2.0, 5.0, inf),
	delta: Pexprand(0.5, 2.0, inf),
	timeScale: Pkey(\sustain) + Pkey(\release),
	ffreqenv: Pfunc({ |ev| [Env([180, exprand(12000, 18000), ev.use { ~freq.value } * 0.9], [0.01, exprand(0.03, 0.2)], \exp)] }),
	rq: Pwhite(0.05, 0.12, inf)
]));

x.set(\rq, Pwhite(0.05, 0.12, inf));
x.set(\degree, Pwrand([
	-14, -10, -9, -6, -5, -3, Pwhite(-1, 11, 1)
], #[1, 1, 1, 2, 2, 2, 10].normalizeSum, inf));
x.set(\ffreqenv, [Env(#[180, 9000, 180], #[0.25, 0.75], \exp)]);
x.set(\ffreqenv, [Env(#[180, 15000, 180], #[0.01, 0.2], \exp)]);

x.set(\ffreqenv, Pfunc({ [Env([180, exprand(1200, 9000), 180], #[0.05, 0.95], \exp)] }));

x.set(\ffreqenv, Pfunc({ |ev| [Env([180, exprand(12000, 18000), ev.use { ~freq.value } * 0.9], [0.01, exprand(0.03, 0.2)], \exp)] }));

x.set(\delta, Pexprand(0.5, 2.0, inf));

p.stop;

m.free;
[b, ~kernel].free;
c.free;


(
PR(\abstractProcess).clone {
	~fftSize = 512;
	~alwaysReset = true;
	~prep = {
		var	cond = Condition.new;
		~chan = MixerChannel(~collIndex, s, 2, 2);
		~event.put(\group, ~chan.synthgroup).put(\out, ~chan.inbus);
		fork {
			~audioKernel = Buffer.read(s,
				thisProcess.nowExecutingPath.dirname +/+ "samp/01-arpeg2.aiff",
				action: {
					cond.unhang;
				}
			);
			cond.hang;
			~kernel = Buffer.alloc(s, PartConv.calcBufSize(~fftSize, ~audioKernel));
			s.sync;
			~kernel.preparePartConv(~audioKernel, ~fftSize);
			s.sync;
			~audioKernel.free;
			SynthDef(\convo, { |outbus, fftsize = 512, kernel, doneAction = 0|
				var	sig = In.ar(outbus, 2);
				sig = Limiter.ar(PartConv.ar(sig, fftsize, kernel));
				DetectSilence.ar(sig.sum, doneAction: doneAction);
				ReplaceOut.ar(outbus, sig);
			}).add;
			"ready".postln;
		};
		SynthDef(\saw, { |freq = 440, amp = 0.1, rq = 1, detuneR = 1.003, attack = 0.1, release = 0.5, gate = 1, timeScale = 1, pan, out|
			var	sig = Saw.ar(freq * [1, detuneR], amp).sum,
			ffreqenv = NamedControl.kr(\ffreqenv,
				(0 ! 32).overWrite(Env(#[2000, 2000], #[1]).asArray)
			),
			ffreq = EnvGen.kr(ffreqenv, timeScale: timeScale);
			sig = RLPF.ar(sig, ffreq, rq);
			sig = sig * EnvGen.kr(Env.asr(attack, 1, release), gate, doneAction: 2);
			Out.ar(out, Pan2.ar(sig, pan));
		}).add;
		~slide = Buffer.read(s, thisProcess.nowExecutingPath.dirname +/+ "samp/01-slide.aiff");
	};
	~freeCleanup = {
		[~chan, ~kernel].free
	};

	~preparePlay = {
		~conv ?? {
			~conv = ~chan.playfx(\convo, [fftsize: ~fftSize, kernel: ~kernel]);
		};
	};
	~stopCleanup = {
		~chan.play((
			instrument: \bufGrainPan,
			bufnum: ~slide,
			time: ~slide.duration,
			amp: 1
		));
		~conv !? {
			~conv.set(\doneAction, 2);
			OSCpathResponder(s.addr, ['/n_end', ~conv.nodeID], e { |t, r, m|
				r.remove;
				~conv = nil;
			}).add;
		};
	};

	~asPattern = {
		Pbind(*[
			instrument: \saw,
			root: 2,
			degree: Pwrand([
				-14, -10, -9, -6, -5, -3, Pwhite(-1, 11, 1)
			], #[1, 1, 1, 2, 2, 2, 10].normalizeSum, inf),
			attack: 0.01,
			release: 1,
			sustain: Pwhite(2.0, 5.0, inf),
			delta: Pexprand(0.5, 2.0, inf),
			timeScale: Pkey(\sustain) + Pkey(\release),
			ffreqenv: Pfunc({ |ev| [Env([180, exprand(12000, 18000), ev.use { ~freq.value } * 0.9], [0.01, exprand(0.03, 0.2)], \exp)] }),
			rq: Pwhite(0.05, 0.12, inf),
			pan: Pwhite(0.7, 1.0, inf) * Prand(#[-1, 1], inf)
		])
	};
} => PR(\i1);
)

BP(\i1).free;
PR(\i1) => BP(\i1);
0 => BP(\i1);
MixingBoard(\x, nil, BP(\i1));

BP(\i1).play;

BP(\i1).stop;

