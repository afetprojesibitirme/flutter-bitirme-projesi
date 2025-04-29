// questions.dart

import 'dart:math';

class Question {
  final String questionText;
  final List<String> options;
  final int correctAnswerIndex;

  Question({
    required this.questionText,
    required this.options,
    required this.correctAnswerIndex,
  });

  // Şıkları ve doğru cevabı karıştıran fonksiyon
  static Question shuffle(Question question) {
    List<String> shuffledOptions = List.from(question.options);
    shuffledOptions.shuffle(Random());
    int newCorrectIndex =
        shuffledOptions.indexOf(question.options[question.correctAnswerIndex]);
    return Question(
      questionText: question.questionText,
      options: shuffledOptions,
      correctAnswerIndex: newCorrectIndex,
    );
  }
}

final List<Question> originalQuestions = [
  Question(
    questionText: "Evinizde bir deprem çantası var mı?",
    options: [
      "Evet, her an ulaşabileceğim bir yerde.",
      "Var ama güncellemedim.",
      "Hayır, hazırlamadım.",
    ],
    correctAnswerIndex: 0,
  ),
  Question(
    questionText:
        "Deprem sırasında nerede durmanız gerektiğini biliyor musunuz?",
    options: [
      "Evet, güvenli alanları biliyorum.",
      "Kısmen, biraz bilgim var.",
      "Hayır, emin değilim.",
    ],
    correctAnswerIndex: 0,
  ),
  Question(
    questionText: "Evdeki ağır eşyaları sabitlediniz mi?",
    options: [
      "Evet, hepsi sabitlenmiş durumda.",
      "Sadece bazılarını sabitledim.",
      "Hayır, sabitlemedim.",
    ],
    correctAnswerIndex: 0,
  ),
  Question(
    questionText: "Elektrik, su ve gaz vanalarını kapatmayı biliyor musunuz?",
    options: [
      "Evet, nasıl kapatacağımı biliyorum.",
      "Kısmen biliyorum.",
      "Hayır, bilmiyorum.",
    ],
    correctAnswerIndex: 0,
  ),
  Question(
    questionText: "Ailenizle acil durum iletişim planı oluşturdunuz mu?",
    options: [
      "Evet, herkes ne yapacağını biliyor.",
      "Kısmen planımız var ama eksiklerimiz var.",
      "Hayır, böyle bir plan yapmadık.",
    ],
    correctAnswerIndex: 0,
  ),
  Question(
    questionText: "Acil durum anında buluşma noktası belirlediniz mi?",
    options: [
      "Evet, belirledik.",
      "Kısmen, düşündük ama netleştirmedik.",
      "Hayır, belirlemedik.",
    ],
    correctAnswerIndex: 0,
  ),
  Question(
    questionText: "Deprem anında en güvenli hareket nedir?",
    options: [
      "Çök, kapan, tutun",
      "Kapıya koşmak",
      "Balkona çıkmak",
    ],
    correctAnswerIndex: 0,
  ),
  Question(
    questionText: "Deprem sonrası ilk yapmanız gereken şey nedir?",
    options: [
      "Güvenli bir şekilde çıkış yolunu kontrol etmek",
      "Telefonla sevdiklerimi hemen aramak",
      "Binada kalıp yardım beklemek",
    ],
    correctAnswerIndex: 0,
  ),
  Question(
    questionText:
        "Deprem sonrası ihtiyaç duyabileceğiniz acil durum malzemelerini (su, yiyecek, ilk yardım çantası vb.) düzenli olarak kontrol ediyor musunuz?",
    options: [
      "Evet, belirli aralıklarla güncelliyorum.",
      "Nadiren kontrol ediyorum.",
      "Hayır, kontrol etmiyorum.",
    ],
    correctAnswerIndex: 0,
  ),
  Question(
    questionText:
        "Bulunduğunuz bina veya evin deprem dayanıklılığı hakkında bilginiz var mı?",
    options: [
      "Evet, risk analizi yaptırdım/güçlendirme yapıldı.",
      "Kısmen biliyorum ama emin değilim.",
      "Hayır, bilmiyorum.",
    ],
    correctAnswerIndex: 0,
  ),
];

// Uygulama başında karıştırılmış sorular listesi oluşturmak için:
List<Question> getShuffledQuestions() {
  return originalQuestions.map((q) => Question.shuffle(q)).toList();
}
