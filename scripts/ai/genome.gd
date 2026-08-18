class_name Genome extends Resource

# Tiny feedforward NN: inputs -> hidden (tanh) -> outputs (tanh)

const INPUTS := 6
const HIDDEN := 8
const OUTPUTS := 2

@export var w1: PackedFloat32Array = PackedFloat32Array()
@export var b1: PackedFloat32Array = PackedFloat32Array()
@export var w2: PackedFloat32Array = PackedFloat32Array()
@export var b2: PackedFloat32Array = PackedFloat32Array()

static func random() -> Genome:
	var g := Genome.new()
	g.w1 = _rand_array(INPUTS * HIDDEN)
	g.b1 = _rand_array(HIDDEN)
	g.w2 = _rand_array(HIDDEN * OUTPUTS)
	g.b2 = _rand_array(OUTPUTS)
	return g

static func _rand_array(n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n: a[i] = randf_range(-1.0, 1.0)
	return a

func forward(inputs: PackedFloat32Array) -> PackedFloat32Array:
	var hidden := PackedFloat32Array()
	hidden.resize(HIDDEN)
	for h in HIDDEN:
		var sum: float = b1[h]
		for i in INPUTS:
			sum += inputs[i] * w1[i * HIDDEN + h]
		hidden[h] = tanh(sum)

	var out := PackedFloat32Array()
	out.resize(OUTPUTS)
	for o in OUTPUTS:
		var sum: float = b2[o]
		for h in HIDDEN:
			sum += hidden[h] * w2[h * OUTPUTS + o]
		out[o] = tanh(sum)
	return out

func mutate(rate: float, strength: float) -> Genome:
	var g := Genome.new()
	g.w1 = _mutate_array(w1, rate, strength)
	g.b1 = _mutate_array(b1, rate, strength)
	g.w2 = _mutate_array(w2, rate, strength)
	g.b2 = _mutate_array(b2, rate, strength)
	return g

func _mutate_array(src: PackedFloat32Array, rate: float, strength: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(src.size())
	for i in src.size():
		a[i] = src[i]
		if randf() < rate:
			a[i] = clamp(a[i] + randf_range(-strength, strength), -3.0, 3.0)
	return a

static func crossover(a: Genome, b: Genome) -> Genome:
	var g := Genome.new()
	g.w1 = _cross_array(a.w1, b.w1)
	g.b1 = _cross_array(a.b1, b.b1)
	g.w2 = _cross_array(a.w2, b.w2)
	g.b2 = _cross_array(a.b2, b.b2)
	return g

static func _cross_array(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(a.size())
	for i in a.size():
		out[i] = a[i] if randf() < 0.5 else b[i]
	return out
