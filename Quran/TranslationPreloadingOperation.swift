//
//  TranslationPreloadingOperation.swift
//  Quran
//
//  Created by Mohamed Afifi on 3/23/17.
//  Copyright © 2017 Quran.com. All rights reserved.
//

import Foundation
import PromiseKit

private struct AyahText {
    let ayah: AyahNumber
    let text: String
}

class TranslationPreloadingOperation: AbstractPreloadingOperation<TranslationPage> {

    let page: Int

    private let localTranslationInteractor: AnyInteractor<Void, [TranslationFull]>
    private let arabicPersistence: AyahTextPersistence
    private let translationPersistenceCreator: AnyCreator<AyahTextPersistence, String>
    private let simplePersistence: SimplePersistence

    init(page                          : Int,
         localTranslationInteractor    : AnyInteractor<Void, [TranslationFull]>,
         arabicPersistence             : AyahTextPersistence,
         translationPersistenceCreator : AnyCreator<AyahTextPersistence, String>,
         simplePersistence             : SimplePersistence) {
        self.page                          = page
        self.simplePersistence             = simplePersistence
        self.arabicPersistence             = arabicPersistence
        self.localTranslationInteractor    = localTranslationInteractor
        self.translationPersistenceCreator = translationPersistenceCreator
    }

    override func main() {

        // get ayahs in the page
        let range = Quran.range(forPage: page)
        let ayahs = range.getAyahs()

        // get the arabic text
        // get the translations text
        // merge them
        when(fulfilled: Promise(value: ayahs), translationsPromise(ayahs: ayahs), arabicPromise(ayahs: ayahs))
            .then(on: .global(), execute: self.merge(ayahs:translations:arabic:))
            .then(execute: self.fulfill)
            .catch(execute: self.reject)
    }

    private func merge(ayahs: [AyahNumber], translations: [(Translation, [AyahText])], arabic: [AyahText]) -> TranslationPage {
        var verses: [TranslationVerse] = []

        for i in 0..<ayahs.count {
            let ayah = ayahs[i]
            let arabicText = arabic[i].text
            let ayahTranslations = translations.map { (translation, ayahs) -> TranslationText in
                let text = ayahs[i].text
                let isLongText = text.characters.count >= 300
                return TranslationText(translation: translation, text: text, isLongText: isLongText)
            }
            let verse = TranslationVerse(ayah: ayah, arabicText: arabicText, translations: ayahTranslations)
            verses.append(verse)
        }

        var prefixes: [String] = []
        if let firstAyah = ayahs.first {
            if firstAyah.startsWithBesmallah {
                prefixes.append(Quran.arabicBasmAllah)
            }
        }
        return TranslationPage(pageNumber: page, arabicPrefix: prefixes, verses: verses, arabicSuffix: [])
    }

    private func translationsPromise(ayahs: [AyahNumber]) -> Promise<[(Translation, [AyahText])]> {
        return localTranslationInteractor
            .execute()
            .then(on: .global(), execute: selectedTranslations(allTranslations:))
            .then(on: .global()) { self.retrieveAllTranslations(ayahs: ayahs, translations: $0) }
    }

    private func selectedTranslations(allTranslations: [TranslationFull]) -> [Translation] {
        let selected = simplePersistence.valueForKey(.selectedTranslations)
        let translationsById = allTranslations.map { $0.translation }.flatGroup { $0.id }
        return selected.flatMap { translationsById[$0] }
    }

    private func arabicPromise(ayahs: [AyahNumber]) -> Promise<[AyahText]> {
        return Promise(value: ayahs).then(on: .global(), execute: retrieveArabicText(ayahs:))
    }

    private func retrieveArabicText(ayahs: [AyahNumber]) throws -> [AyahText] {
        return try ayahs.map(arabicPersistence.getAyahTextWithoutBesmallah(forNumber:))
    }

    private func retrieveAllTranslations(ayahs: [AyahNumber], translations: [Translation]) -> [(Translation, [AyahText])] {
        return translations.map { retrieveTranslationText(ayahs: ayahs, translation: $0) }
    }

    private func retrieveTranslationText(ayahs: [AyahNumber], translation: Translation) -> (Translation, [AyahText]) {
        let fileURL = Files.translationsURL.appendingPathComponent(translation.fileName)
        let persistence = translationPersistenceCreator.create(fileURL.absoluteString)
        var ayahTexts: [AyahText] = []
        for ayah in ayahs {
            let text: String
            do {
                if let ayahText = try persistence.getOptionalAyahText(forNumber: ayah) {
                    text = ayahText
                } else {
                    text = NSLocalizedString("noAvailableTranslationText", comment: "")
                }

            } catch {
                Crash.recordError(error, reason: "Issue getting ayah \(ayah), translation: \(translation.id)", fatalErrorOnDebug: false)
                text = NSLocalizedString("errorInTranslationText", comment: "")
            }
            ayahTexts.append(AyahText(ayah: ayah, text: text))
        }
        return (translation, ayahTexts)
    }
}

extension AyahTextPersistence {
    fileprivate func getOptionalAyahText(forNumber number: AyahNumber) throws -> AyahText? {
        let text = try getOptionalAyahText(forNumber: number)
        return text.map { AyahText(ayah: number, text: $0) }
    }

    fileprivate func getAyahTextWithoutBesmallah(forNumber number: AyahNumber) throws -> AyahText {
        let text = try getAyahTextForNumber(number)
        let besmallah = Quran.arabicBasmAllah + " "
        if number.startsWithBesmallah && text.hasPrefix(besmallah) {
            return AyahText(ayah: number, text: text.substring(from: besmallah.endIndex))
        }
        return AyahText(ayah: number, text: text)
    }
}
