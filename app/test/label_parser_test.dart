import 'package:entreggo/scanning/label_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('etiqueta estilo Mercado Livre', () {
    final p = parseLabel([
      'Mercado Envios',
      'DESTINATÁRIO',
      'Maria Souza',
      'Rua das Flores, 120 - Apto 12',
      'Jardim Paulista',
      'CEP: 01419-001 São Paulo, SP',
      'REMETENTE',
      'Loja Exemplo',
      'Av. Brasil, 500',
      '20040-002 Rio de Janeiro/RJ',
    ]);
    expect(p.address, 'Rua das Flores, 120, Jardim Paulista');
    expect(p.complement, 'Apto 12');
    expect(p.postalCode, '01419-001');
    expect(p.city, 'São Paulo');
    expect(p.state, 'SP');
  });

  test('etiqueta dos Correios com remetente primeiro e número separado', () {
    final p = parseLabel([
      'Remetente: Loja X',
      'Rua A, 1',
      '30110-000 Belo Horizonte - MG',
      'Destinatário',
      'JOÃO DA SILVA',
      'AVENIDA PAULISTA',
      'Nº 1578',
      'BELA VISTA',
      '01310200',
      'SÃO PAULO SP',
      'QB123456789BR',
    ]);
    expect(p.address, 'AVENIDA PAULISTA, 1578, BELA VISTA');
    expect(p.postalCode, '01310-200');
    expect(p.city, 'São Paulo');
    expect(p.state, 'SP');
    expect(p.trackingCode, 'QB123456789BR');
  });

  test('etiqueta sem cabeçalhos', () {
    final p = parseLabel([
      'Pedido 123456',
      'R. Augusta 1500 Bloco B',
      'Consolação',
      'São Paulo/SP 01304-001',
    ]);
    expect(p.address, 'R. Augusta 1500, Consolação');
    expect(p.complement, 'Bloco B');
    expect(p.postalCode, '01304-001');
    expect(p.city, 'São Paulo');
  });

  test('texto sem endereço retorna vazio', () {
    expect(
      parseLabel(['Obrigado pela compra', 'Volte sempre']).isEmpty,
      isTrue,
    );
  });
}
