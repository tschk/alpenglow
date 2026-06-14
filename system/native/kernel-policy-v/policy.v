module main

@[export: 'sol_policy_profile']
pub fn sol_policy_profile() &char {
	return c'internet-appliance'
}

@[export: 'alpenglow_renderer_cpu_weight']
pub fn alpenglow_renderer_cpu_weight() int {
	return 800
}

@[export: 'alpenglow_renderer_memory_high_mb']
pub fn alpenglow_renderer_memory_high_mb() int {
	return 1536
}
