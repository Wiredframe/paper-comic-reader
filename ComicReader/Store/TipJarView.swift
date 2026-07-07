//
//  TipJarView.swift
//  Comic Reader
//
//  The "Leave a tip" sheet: three one-time amounts. Tips are pure support and unlock
//  nothing — that's stated plainly so it's clear there's no paywall.
//

import SwiftUI
import StoreKit

struct TipJarView: View {
    @StateObject private var jar = TipJar()
    @Environment(\.dismiss) private var dismiss

    private let icons = ["cup.and.saucer.fill", "fork.knife", "gift.fill"]

    var body: some View {
        NavigationStack {
            Group {
                if jar.didTip {
                    thanks
                } else {
                    list
                }
            }
            .navigationTitle("Leave a Tip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await jar.load() }
    }

    private var list: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.pink)
                Text("Enjoying Comic Reader?")
                    .font(.title3.bold())
                Text("Comic Reader is free and collects no data. If you'd like to support its development, you can leave a one-time tip. It unlocks nothing — just a thank-you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)

            if jar.loadFailed {
                ContentUnavailableView("Tips unavailable",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text("The tip options couldn't be loaded right now. Please try again later."))
            } else if jar.products.isEmpty {
                ProgressView().padding(.top, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(jar.products.enumerated()), id: \.element.id) { index, product in
                        tipButton(product, icon: icons[min(index, icons.count - 1)])
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
    }

    private func tipButton(_ product: Product, icon: String) -> some View {
        Button {
            Task { await jar.tip(product) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(.body.weight(.semibold))
                    if !product.description.isEmpty {
                        Text(product.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if jar.purchasingID == product.id {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .disabled(jar.purchasingID != nil)
    }

    private var thanks: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Thank you! 💛")
                .font(.title2.bold())
            Text("Your support genuinely helps. Happy reading!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .padding(40)
    }
}
