import 'package:headless_qr/qr.dart';
import 'package:test/test.dart';

void main() {
  group('Basic qr result', () {
    final expected = '''
*******.**..*..*.***..*******
*.....*.*..*...**.*...*.....*
*.***.*..*..*....****.*.***.*
*.***.*.**.*..**...*..*.***.*
*.***.*...*.*.*.**.*..*.***.*
*.....*...***..*..***.*.....*
*******.*.*.*.*.*.*.*.*******
........**...*.**..*.........
*.**.***.**.....*.....*..*.**
..***.......*.**..***.***...*
..*.*.*.****.***.**...*...**.
**.*....**....*..**...**.*..*
**..*.****.**.**.........**..
*.*..*.**.*.*.*.**.*..*....**
**..***..*..****..**..*.*****
**.**..****.****.*.**..*...*.
*..******.***.***..***.**..*.
...*......****..***.......**.
*.*..****.*.**......*.**.**..
........*.*...*.*....*....*..
.**..****..*.*..*.*********..
........***..*.**.*.*...*****
*******.*.*..*.*.****.*.**.*.
*.....*.*.**...****.*...*..**
*.***.*..****.*.*.*.*********
*.***.*.*..*.***..*.**..***.*
*.***.*.*.*..*.*.*..**.*..*.*
*.....*....*.*****..**.*.*.*.
*******.**.*.*...****....*.*.'''.trim();

    test('Check result', () {
      final result = qr('http://www.example.com/ążśźęćńół');
      expect(
          result.map((e) => e.map((v) => v ? '*' : '.').join('')).join('\n'),
          expected
      );
    });
  });
}
