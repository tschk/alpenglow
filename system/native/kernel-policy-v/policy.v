module main

@[export: 'sol_policy_profile']
pub fn sol_policy_profile() &char {
	return c'internet-appliance'
}

@[export: 'sol_renderer_cpu_weight']
pub fn sol_renderer_cpu_weight() int {
	return 800
}

@[export: 'sol_renderer_memory_high_mb']
pub fn sol_renderer_memory_high_mb() int {
	return 1536
}
