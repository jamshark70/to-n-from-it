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
o.free;
o = OSCFunc({ |msg| l.add(msg[3]) }, '/tr', s.addr);

a.free; o.free;

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