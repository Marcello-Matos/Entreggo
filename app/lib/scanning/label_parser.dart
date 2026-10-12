/// Extrai o endereço do destinatário a partir das linhas de texto lidas de uma etiqueta.
///
/// Heurística para etiquetas brasileiras (Mercado Livre, Shopee, Correios, Amazon...):
/// considera apenas o bloco do destinatário, localiza CEP, cidade/UF e a linha do logradouro.
/// O nome do destinatário é ignorado de propósito (minimização de dados - LGPD).
class ParsedLabel {
  const ParsedLabel({
    this.address,
    this.city,
    this.state,
    this.postalCode,
    this.complement,
    this.trackingCode,
  });

  final String? address;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? complement;
  final String? trackingCode;

  bool get isEmpty => address == null && postalCode == null;
}

const _ufs = {
  'AC',
  'AL',
  'AP',
  'AM',
  'BA',
  'CE',
  'DF',
  'ES',
  'GO',
  'MA',
  'MT',
  'MS',
  'MG',
  'PA', //
  'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO',
};

final _cep = RegExp(r'\b(\d{5})[-.\s]?(\d{3})\b');
final _street = RegExp(
  r'^(rua|r|av|avenida|alameda|al|travessa|tv|trav|estrada|estr|'
  r'rodovia|rod|pra[cç]a|p[cç]a|largo|lgo|via|viela|servid[aã]o|beco|'
  r'quadra|qd|setor|conjunto|conj|ladeira|parque|condom[ií]nio)(\.|\b)',
  caseSensitive: false,
);
final _numberLine = RegExp(
  r'^(n[º°o.]?|n[uú]mero)\s*[:.]?\s*(\d+\w?)',
  caseSensitive: false,
);
final _complement = RegExp(
  r'\b(ap(to|t)?\.?|apartamento|bloco|bl\.?|casa|fundos|sala|loja|andar|lote|'
  r'complemento|comp\.?)\b',
  caseSensitive: false,
);
final _label = RegExp(
  r'^(endere[cç]o|logradouro|bairro|cidade)\s*:\s*',
  caseSensitive: false,
);
final _tracking = RegExp(r'\b([A-Z]{2}\d{9}[A-Z]{2}|\d{10,14})\b');
final _noise = RegExp(
  r'(remetente|destinat[aá]ri|refer[eê]ncia|telefone|tel\.|cpf|cnpj|nota fiscal|nf-?e|'
  r'pedido|volume|peso|envio|transportadora|data|assinatura|recebedor)',
  caseSensitive: false,
);

ParsedLabel parseLabel(List<String> rawLines) {
  final lines = [
    for (final l in rawLines)
      if (l.trim().isNotEmpty) l.trim().replaceAll(RegExp(r'\s+'), ' '),
  ];
  final scope = _recipientBlock(lines);

  final cepIndex = scope.indexWhere(_cep.hasMatch);
  String? postalCode;
  String? city;
  String? state;
  if (cepIndex >= 0) {
    final m = _cep.firstMatch(scope[cepIndex])!;
    postalCode = '${m[1]}-${m[2]}';
    (city, state) = _cityState(
      scope[cepIndex]
          .replaceAll(m[0]!, ' ')
          .replaceAll(RegExp(r'cep\s*:?', caseSensitive: false), ' '),
    );
    // Cidade/UF na linha seguinte ou anterior ao CEP.
    for (final i in [cepIndex + 1, cepIndex - 1]) {
      if (city != null || i < 0 || i >= scope.length) continue;
      (city, state) = _cityState(scope[i]);
    }
  } else {
    for (final l in scope) {
      if (city != null) break;
      (city, state) = _cityState(l);
    }
  }

  final streetIndex = scope.indexWhere(
    (l) => _street.hasMatch(l.replaceFirst(_label, '')),
  );
  String? address;
  String? complement;
  if (streetIndex >= 0) {
    var street = scope[streetIndex].replaceFirst(_label, '');
    // Separa complemento ("Rua X, 120 - Apto 12" / "Rua X, 120 Bloco B").
    final dash = street.indexOf(RegExp(r'\s[-–]\s'));
    if (dash > 0) {
      final tail = street
          .substring(dash)
          .replaceFirst(RegExp(r'^\s[-–]\s'), '')
          .trim();
      street = street.substring(0, dash).trim();
      if (_complement.hasMatch(tail)) {
        complement = tail;
      } else if (tail.isNotEmpty && !RegExp(r'\d').hasMatch(street)) {
        street = '$street, $tail';
      }
    } else {
      final c = _complement.firstMatch(street);
      if (c != null && c.start > 0) {
        complement = street.substring(c.start).trim();
        street = street
            .substring(0, c.start)
            .trim()
            .replaceAll(RegExp(r'[,\s]+$'), '');
      }
    }
    // Número em linha separada ("Nº 120").
    final next = streetIndex + 1 < scope.length ? scope[streetIndex + 1] : '';
    final number = _numberLine.firstMatch(next);
    if (!RegExp(r'\d').hasMatch(street) && number != null) {
      street = '$street, ${number[2]}';
    }
    // Bairro: primeira linha "limpa" entre o logradouro e o CEP/cidade.
    final end = cepIndex > streetIndex ? cepIndex : scope.length;
    for (var i = streetIndex + 1; i < end && i <= streetIndex + 3; i++) {
      final l = scope[i];
      final isBairro = RegExp(r'^bairro\s*:', caseSensitive: false).hasMatch(l);
      if (_numberLine.hasMatch(l) || _noise.hasMatch(l) || _cep.hasMatch(l)) {
        continue;
      }
      if (_complement.hasMatch(l) && !isBairro) {
        complement ??= l;
        continue;
      }
      final cityOnly = _cityState(l);
      if (cityOnly.$1 != null && cityOnly.$1 == city) continue;
      street = '$street, ${l.replaceFirst(_label, '')}';
      break;
    }
    address = street;
  }

  final trackingCode = _tracking.firstMatch(lines.join(' '))?.group(1);
  return ParsedLabel(
    address: address,
    city: city,
    state: state,
    postalCode: postalCode,
    complement: complement,
    trackingCode: trackingCode,
  );
}

/// Linhas do bloco do destinatário, excluindo o bloco do remetente quando identificável.
List<String> _recipientBlock(List<String> lines) {
  bool isHeader(String l, String word) => RegExp(
    '^$word',
    caseSensitive: false,
  ).hasMatch(l.replaceAll(RegExp(r'[^A-Za-zÀ-ú]'), ''));
  final dest = lines.indexWhere((l) => isHeader(l, 'destinat'));
  final sender = lines.indexWhere((l) => isHeader(l, 'remetente'));
  if (dest >= 0) {
    final end = sender > dest ? sender : lines.length;
    return lines.sublist(dest + 1, end);
  }
  if (sender >= 0) {
    // Remetente primeiro: o destinatário costuma vir depois do primeiro CEP.
    final senderCep = lines.indexWhere(_cep.hasMatch, sender);
    if (senderCep >= 0 && senderCep + 1 < lines.length) {
      return lines.sublist(senderCep + 1);
    }
    return lines.sublist(0, sender);
  }
  return lines;
}

/// Reconhece "São Paulo/SP", "São Paulo - SP", "São Paulo, SP", "SÃO PAULO SP".
(String?, String?) _cityState(String text) {
  final cleaned = text.replaceFirst(_label, '').trim();
  final m = RegExp(
    r"([A-Za-zÀ-ú][A-Za-zÀ-ú\s.'-]{1,40}?)\s*(?:[/,-]|\s)\s*([A-Za-z]{2})\.?$",
  ).firstMatch(cleaned);
  if (m == null) return (null, null);
  final uf = m[2]!.toUpperCase();
  if (!_ufs.contains(uf)) return (null, null);
  final city = m[1]!.trim().replaceAll(RegExp(r'[-,/]+$'), '').trim();
  if (city.isEmpty || _street.hasMatch(city) || _noise.hasMatch(city)) {
    return (null, null);
  }
  return (_titleCase(city), uf);
}

String _titleCase(String s) {
  const lower = {'de', 'da', 'do', 'das', 'dos', 'e'};
  return s
      .toLowerCase()
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map(
        (w) => lower.contains(w) ? w : '${w[0].toUpperCase()}${w.substring(1)}',
      )
      .join(' ')
      .replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase());
}
