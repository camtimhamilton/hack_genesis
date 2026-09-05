# frozen_string_literal: true

require_relative '../test_helper'

describe 'Hard-constraints (spec.md §5.1)' do
  include TestFixtures

  let(:filter) { HardFilter.new }
  let(:op) { fixture_op }

  it 'допускает провайдера при отсутствии нарушений' do
    ok, reason, = filter.eligible?(op, fixture_provider)
    _(ok).must_equal true
    _(reason).must_be_nil
  end

  it 'исключает провайдера со статусом не active' do
    ok, reason, = filter.eligible?(op, fixture_provider('status' => 'paused'))
    _(ok).must_equal false
    _(reason).must_equal 'inactive_provider'
  end

  it 'исключает внешнего провайдера с нулевым трафиком, но оставляет fallback' do
    external = fixture_provider('traffic_percentage' => 0)
    fallback = spacepayments_provider
    _(filter.eligible?(op, external).first).must_equal false
    _(filter.eligible?(op, fallback).first).must_equal true
  end

  it 'проверяет нижнюю границу суммы' do
    p = fixture_provider('limit_amount_min' => 5000)
    _(filter.eligible?(op, p)[1]).must_equal 'amount_below_minimum'
  end

  it 'проверяет верхнюю границу суммы' do
    p = fixture_provider('limit_amount_max' => 500)
    _(filter.eligible?(op, p)[1]).must_equal 'amount_exceeds_limit'
  end

  it 'проверяет дневной лимит' do
    p = fixture_provider('daily_amount_limit' => 1000, 'daily_approved_amount' => 500)
    _(filter.eligible?(op, p)[1]).must_equal 'daily_limit_exceeded'
  end

  it 'проверяет лимит in-progress count' do
    p = fixture_provider('in_progress_count_limit' => 1, 'in_progress_count' => 1)
    _(filter.eligible?(op, p)[1]).must_equal 'in_progress_limit_exceeded'
  end

  it 'проверяет лимит in-progress amount' do
    p = fixture_provider('in_progress_amount_limit' => 1000, 'in_progress_amount' => 500)
    _(filter.eligible?(op, p)[1]).must_equal 'in_progress_limit_exceeded'
  end

  it 'проверяет наличие реквизитов' do
    p = fixture_provider('available_requisites' => 0)
    _(filter.eligible?(op, p)[1]).must_equal 'no_available_requisites'
  end

  it 'проверяет отрицательную маржу' do
    p = fixture_provider('provider_margin_pct' => 2.0, 'merchant_margin_pct' => 1.5)
    _(filter.eligible?(op, p)[1]).must_equal 'negative_margin'
  end

  it 'проверяет банковский фильтр' do
    p = fixture_provider('banks' => ['sberbank'])
    _(filter.eligible?(fixture_op('bank' => 'alfa'), p)[1]).must_equal 'bank_not_in_list'
  end

  it 'null-лимиты трактуются как «без ограничения»' do
    p = fixture_provider('limit_amount_min' => nil, 'limit_amount_max' => nil, 'daily_amount_limit' => nil)
    _(filter.eligible?(op, p).first).must_equal true
  end
end
