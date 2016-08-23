
proc say_hello() {
  writeln("Hello from locale with name ", here.name, " and id ", here.id);
  writeln("We are in sublocale id ", here.sublocid);
}

on (Locales[0]:LocaleModel).GPU do {
  say_hello();
}

on (Locales[0]:LocaleModel).CPU do {
  say_hello();
}

on Locales[0] do {
  say_hello();
}
