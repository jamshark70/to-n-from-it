s.boot;

(
PR(\abstractProcess).clone {
	~fftSize = 512;
	~alwaysReset = true;
	~prep = {
		var	cond = Condition.new;
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
			FreeVerb2.ar(out[0], out[1], mix, room, damp);
		}, [
			#[0, 128, \lin, 1, 0], StaticSpec(1, 8, \lin, 1, 1), StaticSpec(1, 8, \lin, 1, 3),
			#[0.01, 1, \exp, 0, 0.1], #[0.001, 0.05, \exp, 0, 0.01], #[0.001, 0.05, \exp, 0, 0.01],
			#[0, 1], #[0, 1], #[0, 1]
		]);
		~chan = MixerChannel(~collIndex, s, 2, 2, level: -20.dbamp, completionFunc: { |chan|
			~chorusVerb = chan.playfx(Instr("busfx.cverb"), [0, 2, 3, 0.079652607331209, 0.00940827137815, 0.02950861451756, 0.33000001311302, 0.7752999663353, 0.37079998850822]);
		});
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
		[~chan, ~kernel].free;
		~convEndResp.remove;
	};

	~preparePlay = {
		~conv ?? {
			s.makeBundle(nil, {
				~conv = ~chan.playfx(\convo, [fftsize: ~fftSize, kernel: ~kernel]);
				~conv.moveToHead(~chan.effectgroup);
			});
			~convEndResp = OSCpathResponder(s.addr, ['/n_end', ~conv.nodeID], e { |t, r, m|
				r.remove;
				~convEndResp = nil;
				~conv = nil;
			}).add;
		};
	};
	~stopCleanup = {
		if(~conv.notNil) {
			~chan.play((
				instrument: \bufGrainPan,
				bufnum: ~slide,
				time: ~slide.duration,
				amp: 1
			));
		};
		~conv !? {
			~conv.set(\doneAction, 2);
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

BP(\i1).free;
PR(\i1) => BP(\i1);
0 => BP(\i1);
MixingBoard(\x, nil, BP(\i1));
)

/*
BP(\i1).play;
BP(\i1).stop;
*/


(
// processDur is the # of seconds BP(\i1) will be allowed to play
// it will continue to ring some seconds after stopping,
// so the total duration will be 8-10 seconds longer than this
var processDur = 15;

if(t.notNil and: { t.isRunning }) { t.stop };
t = TLSequenceIterator([
	funcCmd: (
		setDoneSignal: {
			~doneSignal = OSCresponderNode(s.addr, '/n_go', e { |t, r, m|
				if(BP(\i1).chan.recProxy.notNil) {
					if(m[1] == BP(\i1).chan.recProxy.synth.nodeID) {
						~stop.();
					};
				};
			}).add;
		},
		func: {
			BP(\i1).chan.startRecord;
		},
		clearDoneSignal: { ~doneSignal.remove }
	),
	\cmdSync,
	0.1,
	bpCmd: (name: \i1, dur: processDur),
	\sync,
	12,
	{ BP(\i1).chan.stopRecord; 0 }
]).play;
)

BP(\i1).chan.stopRecord;  // for emergencies