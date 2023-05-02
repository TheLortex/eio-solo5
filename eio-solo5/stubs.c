#include <solo5.h>


#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/callback.h>
#include <caml/alloc.h>
#include <sys/time.h>
#include <unistd.h>



CAMLprim value
caml_get_monotonic_time(value v_unit)
{
  CAMLparam1(v_unit);
  CAMLreturn(caml_copy_int64(solo5_clock_monotonic()));
}

CAMLprim value
mirage_solo5_yield_2(value v_deadline)
{
    CAMLparam1(v_deadline);

    solo5_time_t deadline = (Int64_val(v_deadline));
    solo5_handle_set_t ready_set;
    solo5_yield(deadline, &ready_set);

    CAMLreturn(caml_copy_int64(ready_set));
}
