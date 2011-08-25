// init
(
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

~dir = thisProcess.nowExecutingPath.dirname;

s.waitForBoot {
	b.free;
	b = Array.fill(2, { |i| Buffer.readChannel(s, (~dir +/+ "samp/04-g9.aiff"), channels: [i]) });
	m = MixerChannel('04-many', s, 2, 2, level: -25.dbamp, completionFunc: { |chan|
		~chorusVerb = chan.playfx(Instr("busfx.cverb"), [0, 2, 3, 0.079652607331209, 0.00940827137815, 0.02950861451756, 0.33000001311302, 0.7752999663353, 0.37079998850822]);
	});
	MixingBoard(\x, nil, m);

	SynthDef(\buzz, { |bufnum, tfreq, start, gdur = 0.1, rate = 1, pan, panMul = 1,
		dratio = 0.25, lpfreq = 19000, releaseTime = 2, gate = 1, out|
		var	trig = Impulse.ar(tfreq),
			graindur = min(gdur, (1.0 - start) / rate * BufDur.kr(bufnum)),
			sig = GrainBuf.ar(2, trig, graindur, bufnum, rate,
				start, pan: pan * panMul, envbufnum: -1
			),
			sr = SampleRate.ir;
		sig = Latch.ar(sig, Impulse.ar(sr * dratio));
		sig = LPF.ar(sig.round(0.01), lpfreq)
		* EnvGen.kr(Env.asr(0.01, 1, releaseTime, -7), gate, doneAction: 2);
		Out.ar(out, sig)
	}).add;
};
)


// record

(
var dur = 30, release = 5;
if(t.tryPerform(\isRunning) ? false) { t.stop };
t = TLSequenceIterator([
	funcCmd: (
		func: {
			m.startRecord;
		},
		setDoneSignal: {
			~doneSignal = OSCresponderNode(s.addr, '/n_go', e { |time, resp, msg|
				if(msg[1] == m.recProxy.tryPerform(\synth).tryPerform(\nodeID)) {
					~stop.()
				};
			}).add;
		},
		clearDoneSignal: { ~doneSignal.remove }
	),
	\cmdSync,
	{
		~tfreq = GenericGlobalControl(\tfreq, nil, 18, #[1, 20]);
		~start = GenericGlobalControl(\start, nil, 0.05);
		~dur = GenericGlobalControl(\dur, nil, 1, #[0.1, 5]);
		~pan = GenericGlobalControl(\pan, nil, 0, \bipolar);
		~dratio = GenericGlobalControl(\dratio, nil, 0.25);
		~lpfreq = GenericGlobalControl(\lpfreq, nil, 19000, \freq);
		0
	},
	gcAutoSynthCmd: (gc: e { ~start }, outName: \out,
		/*name: \ctlEnv,*/ time: { ~dur ? 1 }, connect: 0, dur: dur + release,
		// env: Env(#[0.6, 0.01, 0.1], #[0.9, 0.1], \sin)
		id: \startctl,
		name: {
			max(0, EnvGen.kr(Env(#[0.6, 0.2, 0.0, 0.1], [dur - 0.5, 0.4, release + 0.1], \sin))
				+ LFDNoise1.kr(LFNoise1.kr(1.2).range(0.2, 3), 0.03))
		}
	),
	gcAutoSynthCmd: (gc: e { ~pan }, outName: \out,
		name: { LFNoise1.kr(7) * XLine.kr(0.01, 1, dur, doneAction: 2) }
	),
	gcAutoSynthCmd: (gc: e { ~dratio }, outName: \outbus,
		name: \ctlEnv, time: { ~dur ? 1 }, connect: 0, dur: dur + release,
		env: Env(#[0.8, 0.08], #[1], 4)
	),
	gcAutoSynthCmd: (gc: e { ~tfreq }, outName: \outbus,
		name: \ctlEnv, time: { ~dur ? 1 }, connect: 0, dur: dur,
		env: Env(#[6, 18], #[1], \sin)
	),
	gcAutoSynthCmd: (gc: e { ~dur }, outName: \out,
		name: { (topEnvironment[\tfreq].kr * 20) }
	),
	// gcAutoSynthCmd: (gc: e { ~start }, outName: \outbus,
	// 	name: \ctlEnv, time: { ~dur ? 1 }, connect: 0,
	// 	env: 
	// ),
	{
		// damn lazy init
		PR(\synthCmd).copy.putAll((
			id: \bz, name: \buzz, target: m.synthgroup, out: m.inbus, bufnum: b[0],
			tfreq: ~tfreq.asMap, start: ~start.asMap, gdur: ~dur.asMap, pan: ~pan.asMap,
			dratio: ~dratio.asMap, lpfreq: ~lpfreq.asMap,
			dur: dur, releaseTime: release
		))
	},
	{
		// damn lazy init
		PR(\synthCmd).copy.putAll((
			id: \bz2, name: \buzz, target: m.synthgroup, out: m.inbus, bufnum: b[1],
			tfreq: ~tfreq.asMap, start: ~start.asMap, gdur: ~dur.asMap, pan: ~pan.asMap,
			dratio: ~dratio.asMap, lpfreq: ~lpfreq.asMap, panMul: -1,
			dur: dur, releaseTime: release
		))
	},
	// synthCmd ends after 'dur' beats, but I need to wait until the synth is gone
	funcCmd: (
		setDoneSignal: {
			~doneSignal = SimpleController(~iterator.findActive(\bz).node)
				.put(\n_end, e { ~stop.() });
		},
		clearDoneSignal: { ~doneSignal.remove }
	),
	\cmdSync,
	funcCmd: (func: {
		"done".postln;
		~iterator.activeCmds.copy.do { |cmd|
			if(cmd !== currentEnvironment) { cmd.stop };
		};
	})
]).play;
u.remove;
u = SimpleController(t).put(\done, {
	u.remove;
	"freeing gcs".debug;
	[~tfreq, ~start, ~dur, ~pan, ~dratio, ~lpfreq].free;
	m.stopRecord;
});
)