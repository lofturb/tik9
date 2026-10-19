// TTTunelCompat.cc -- lo poco que hay que poner para que BoringSSL enlace en iOS 9.
//
// BoringSSL es C++ por dentro y usa std::optional (std::optional::value()), que
// cuando el optional esta vacio llama a std::__1::__throw_bad_optional_access().
// Ese simbolo no lo trae el libc++ del sistema hasta iOS 11, asi que el
// enlazador se pararia con "undefined symbol".
//
// Aqui se pone el nuestro.  En el codigo de BoringSSL ese camino no se toma
// nunca (los optional que usa vienen siempre con valor), asi que esta funcion es
// un seguro que no llega a llamarse: si algun dia se llamara, aborta, que es
// infinitamente mejor que seguir con datos a medias.
//
// Es el precio de compilar una biblioteca de 2025 contra un sistema de 2015, y
// esta pagado en un solo sitio y a la vista.  Ver tools/compilar_tunel.sh
// (bandera _LIBCPP_DISABLE_AVAILABILITY) y app/TTTunel.c.

#include <stdlib.h>

namespace std {
namespace __1 {

__attribute__((noreturn)) void __throw_bad_optional_access() {
    abort();
}

}  // namespace __1
}  // namespace std
