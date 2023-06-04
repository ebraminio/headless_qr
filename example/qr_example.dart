import 'package:headless_qr/qr.dart';

void main() {
  var result = qr('http://www.example.com/ążśźęćńół');
  print(result.map((e) => e.map((v) => v ? '*' : '.').join('')).join('\n'));
}
