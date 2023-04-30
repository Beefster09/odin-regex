package regex
import "core:fmt"
import "core:testing"
import "core:strings"
import "core:strconv"
import "core:intrinsics"
import "core:time"
import _spall "core:prof/spall"
spall :: _spall
spall_ctx: spall.Context
spall_buffer: spall.Buffer

ENABLE_SPALL :: #config(ENABLE_SPALL, false)
freq: u64 = 3_500_000_000 // Assumed Processor Speed - 3.5 ghz
when ENABLE_SPALL {
	TRACE :: spall.SCOPED_EVENT
} else {
	TRACE :: proc(ctx: ^spall.Context, buf: ^spall.Buffer, name: string) {}
}
///
main :: proc() {
	when ENABLE_SPALL {
		spall_ctx = spall.context_create("regex.spall")
		defer spall.context_destroy(&spall_ctx)
		buffer_backing := make([]u8, spall.BUFFER_DEFAULT_SIZE)
		spall_buffer = spall.buffer_create(buffer_backing)
		defer spall.buffer_destroy(&spall_ctx, &spall_buffer)
		freq, _ = time.tsc_frequency() // <-- VERY slow call
	}
	TRACE(&spall_ctx, &spall_buffer, #procedure)

	regex := "a(bc)+"
	p := init_parser(regex)
	// AST of Regex Inputs:
	expr, err := parse_expr(&p);defer destroy_expr(&expr)
	nfa := compile_nfa(expr);defer destroy_nfa(&nfa)
	for t, i in nfa.transitions {fmt.printf("State: %v, %v\n", i, t)}
	fmt.printf("start:%v, end:%v\n", nfa.start, nfa.end)

	str := "abcbc"

	m := match(&nfa, str)
	fmt.printf("regex:\"%s\", str:\"%s\", matches: %v\n", regex, str, m)
	// sb := strings.builder_make()
	// print_ast(&expr, &sb)
	// fmt.println(strings.to_string(sb))
}

tests := map[string]string {
	"\\w+"                        = "testing_123",
	"0x[0-9a-fA-F_]{2,}"          = "0x2A19_42DD",
	"(a|b)+c?d*"                  = "abababcdddd", // "cd" false
	"[a-zA-Z_]\\w*\\s*::\\s*proc" = "foo :: proc",
}
import "core:slice"
@(test)
test_perf :: proc(t: ^testing.T) {
	// NOTE: Should run this test with: `odin test . -o:speed -disable-assert -no-bounds-check`
	regex := "([0-9]+)-([0-9]+)-([0-9]+)"
	p := init_parser(regex)
	expr, err := parse_expr(&p);defer destroy_expr(&expr)
	nfa := compile_nfa(expr);defer destroy_nfa(&nfa)
	str := "650-253-0001"
	when false {freq, _ = time.tsc_frequency()} 	// Accurate Freq - its very slow to start, >1s
	results := [dynamic]f64{};defer delete(results)
	n_runs := 100
	// Best of n-match with rdtsc:
	for i := 0; i < n_runs; i += 1 {
		start_tsc := intrinsics.read_cycle_counter()
		m := match(&nfa, str)
		clocks := f64(intrinsics.read_cycle_counter() - start_tsc)
		append(&results, clocks)
	}
	f_mult := f64(freq) / f64(1_000_000_000)
	sum: f64
	min_clock: f64 = f64(1 << 16)
	max_clock: f64
	for r in results {sum += r;min_clock = min(min_clock, r);max_clock = max(max_clock, r)}
	mean := sum / f64(len(results))
	slice.sort(results[:])
	median := results[len(results) / 2]
	fmt.printf("Performance for `%v` and str: `%v` (n_runs: %v)\n", regex, str, n_runs)
	fmt.printf("(nanoseconds): Min: %.0f, Max: %.0f, Median: %.0f, Mean: %.0f\n", min_clock, max_clock, median, mean)
	// objective :: <1us - c/odin perf is ~2x in regex, spall is another 2x cost when on
}

@(test)
test_optional :: proc(t: ^testing.T) {
	regex := "a?"
	p := init_parser(regex)
	expr, err := parse_expr(&p);defer destroy_expr(&expr)
	nfa := compile_nfa(expr);defer destroy_nfa(&nfa)
	{
		str := "b"
		m := match(&nfa, str)
		assert(m == false, "b matched a?")
	};{
		str := "a"
		m := match(&nfa, str)
		assert(m == true, "a did not match a?")
	};{
		str := ""
		m := match(&nfa, str)
		assert(m == true, "'' did not match `a?`")
	}
}
@(test)
test_asterisk :: proc(t: ^testing.T) {
	regex := "a*"
	p := init_parser(regex)
	expr, err := parse_expr(&p);defer destroy_expr(&expr)
	nfa := compile_nfa(expr);defer destroy_nfa(&nfa)
	{
		str := "b"
		m := match(&nfa, str)
		assert(m == false, "b matched a*")
	};{
		str := ""
		m := match(&nfa, str)
		assert(m == true, "'' did not match `a*`")
	};{
		str := "a"
		m := match(&nfa, str)
		assert(m == true, "a did not match a*")
	};{
		str := "aaa"
		m := match(&nfa, str)
		assert(m == true, "aaa did not match a*")
	}
}
@(test)
test_plus :: proc(t: ^testing.T) {
	regex := "a+"
	p := init_parser(regex)
	expr, err := parse_expr(&p);defer destroy_expr(&expr)
	nfa := compile_nfa(expr);defer destroy_nfa(&nfa)
	{
		str := "b"
		m := match(&nfa, str)
		assert(m == false, "b matched a+")
	};{
		str := ""
		m := match(&nfa, str)
		assert(m == false, "'' matched `a+`")
	};{
		str := "a"
		m := match(&nfa, str)
		assert(m == true, "a did not match a+")
	};{
		str := "aaa"
		m := match(&nfa, str)
		assert(m == true, "aaa did not match a+")
	}
}
@(test)
test_alt :: proc(t: ^testing.T) {
	regex := "a|b"
	p := init_parser(regex)
	expr, err := parse_expr(&p);defer destroy_expr(&expr)
	nfa := compile_nfa(expr);defer destroy_nfa(&nfa)
	{
		str := ""
		m := match(&nfa, str)
		assert(m == false, "'' matched a|b")
	};{
		str := "a"
		m := match(&nfa, str)
		assert(m == true, "a did not match a|b")
	};{
		str := "b"
		m := match(&nfa, str)
		assert(m == true, "b did not match a|b")
	};{
		str := "c"
		m := match(&nfa, str)
		assert(m == false, "c matched a|b")
	}
}
