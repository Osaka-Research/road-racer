extends Node3D

# Neuroevolution trainer: races a population of AUTO-mode vehicles on the
# track simultaneously (they don't collide with each other), scores each by
# forward progress minus wall-hugging, then breeds the next generation.
# Run headless: godot --headless --fixed-fps 60 --audio-driver Dummy scenes/training.tscn

const VehicleScene := preload("res://scenes/vehicle.tscn")

@export var population_size := 10
@export var generations := 40
@export var episode_seconds := 30.0
@export var mutation_rate := 0.12
@export var mutation_strength := 0.5
@export var elite_count := 3
@export var overtake_bonus := 2.0  # fitness per rival this genome out-progressed

var population: Array[Genome] = []
var vehicles: Array[Vehicle] = []
var progress: Array[float] = []    # farthest distance ever reached from spawn
var penalty: Array[float] = []     # accumulated wall-hug + collision + stuck penalty
var prev_collisions: Array[int] = []
var stuck_time: Array[float] = []  # seconds spent near-stationary (wedged against something)
var start_transform: Transform3D
var start_pos: Vector3
var elapsed := 0.0
var generation := 0
var best_genome: Genome = null
var best_fitness := -INF

func _ready() -> void:
	start_transform = $SpawnPoint.global_transform
	start_pos = start_transform.origin
	for i in population_size:
		population.append(Genome.random())
	_spawn_generation()

func _spawn_generation() -> void:
	for v in vehicles:
		v.queue_free()
	vehicles.clear()
	progress.clear()
	penalty.clear()
	prev_collisions.clear()
	stuck_time.clear()
	elapsed = 0.0

	for i in population_size:
		var v: Vehicle = VehicleScene.instantiate()
		add_child(v)
		v.global_transform = start_transform
		v.autopilot = true
		v.autopilot_brain = population[i]
		(v.get_node("Sphere") as RigidBody3D).collision_mask = 1  # track only; cars must not interfere with each other's fitness
		vehicles.append(v)
		progress.append(0.0)
		penalty.append(0.0)
		prev_collisions.append(0)
		stuck_time.append(0.0)

func _physics_process(delta: float) -> void:
	elapsed += delta

	for i in vehicles.size():
		var v = vehicles[i]

		# Reward is farthest distance ever ventured from the spawn point, not
		# raw speed -- walls then force real progress along the track instead
		# of letting the car reward-hack by donuting safely near spawn.
		var d: float = v.get_vehicle_position().distance_to(start_pos)
		if d > progress[i]:
			progress[i] = d

		# Soft shaping: discourage hugging walls before they actually hit
		if v.side_touching_wall():
			penalty[i] += 1.0 * delta

		# Hard penalty: an actual physical collision with the track
		if v.collision_count > prev_collisions[i]:
			penalty[i] += 8.0 * (v.collision_count - prev_collisions[i])
			prev_collisions[i] = v.collision_count

		# Getting wedged and giving up is as bad as crashing: penalize sitting
		# near-stationary for too long instead of reversing/steering out
		if absf(v.linear_speed) < 0.05:
			stuck_time[i] += delta
		else:
			stuck_time[i] = 0.0
		if stuck_time[i] > 1.5:
			penalty[i] += 3.0 * delta

	if elapsed >= episode_seconds:
		_end_generation()

func _end_generation() -> void:
	var fitness: Array[float] = []
	for i in population_size:
		fitness.append(progress[i] - penalty[i])

	# Competitive bonus: reward out-progressing rivals, not just solo distance --
	# the population races the same track at the same time (see _spawn_generation),
	# and each vehicle can now sense the nearest rival (see Vehicle.handle_autopilot),
	# so this gives evolution actual pressure to navigate around a rival ahead
	# instead of just being ignored as fitness-irrelevant.
	for i in population_size:
		var beaten := 0
		for j in population_size:
			if j != i and progress[i] > progress[j]:
				beaten += 1
		fitness[i] += beaten * overtake_bonus

	var order := range(population_size)
	order.sort_custom(func(a, b): return fitness[a] > fitness[b])

	var gen_best: float = fitness[order[0]]
	var avg_hits := 0.0
	for v in vehicles: avg_hits += v.collision_count
	avg_hits /= vehicles.size()
	print("gen %d best=%.2f (progress=%.1f) avg=%.2f avg_hits=%.1f" % [generation, gen_best, progress[order[0]], _avg(fitness), avg_hits])

	if gen_best > best_fitness:
		best_fitness = gen_best
		best_genome = population[order[0]]
		ResourceSaver.save(best_genome, "res://ai/best_genome.tres")

	var next_pop: Array[Genome] = []
	for i in elite_count:
		next_pop.append(population[order[i]])

	var pool_size := mini(elite_count * 3, population_size)
	while next_pop.size() < population_size:
		var pa: Genome = population[order[randi_range(0, pool_size - 1)]]
		var pb: Genome = population[order[randi_range(0, pool_size - 1)]]
		next_pop.append(Genome.crossover(pa, pb).mutate(mutation_rate, mutation_strength))

	population = next_pop
	generation += 1

	if generation >= generations:
		print("training done, best fitness=%.2f" % best_fitness)
		get_tree().quit()
		return

	_spawn_generation()

func _avg(arr: Array[float]) -> float:
	var s := 0.0
	for x in arr:
		s += x
	return s / arr.size()
