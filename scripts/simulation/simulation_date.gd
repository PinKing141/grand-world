class_name SimulationDate
extends RefCounted

const START_YEAR := 1444
const START_MONTH := 11
const START_DAY := 11


static func is_leap_year(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


static func days_in_month(year: int, month: int) -> int:
	match month:
		1, 3, 5, 7, 8, 10, 12:
			return 31
		4, 6, 9, 11:
			return 30
		2:
			return 29 if is_leap_year(year) else 28
		_:
			return 0


static func day_to_date(day_count: int) -> Dictionary:
	var remaining := maxi(day_count, 0)
	var year := START_YEAR
	var month := START_MONTH
	var day := START_DAY
	while remaining > 0:
		var available := days_in_month(year, month) - day
		if remaining <= available:
			day += remaining
			remaining = 0
		else:
			remaining -= available + 1
			day = 1
			month += 1
			if month > 12:
				month = 1
				year += 1
	return {"year": year, "month": month, "day": day}


static func date_to_day(year: int, month: int, day: int) -> int:
	if not is_valid_date(year, month, day):
		return -1
	if _compare_dates(year, month, day, START_YEAR, START_MONTH, START_DAY) < 0:
		return -1
	var current_year := START_YEAR
	var current_month := START_MONTH
	var current_day := START_DAY
	var result := 0
	while current_year != year or current_month != month or current_day != day:
		result += 1
		current_day += 1
		if current_day > days_in_month(current_year, current_month):
			current_day = 1
			current_month += 1
			if current_month > 12:
				current_month = 1
				current_year += 1
	return result


static func is_valid_date(year: int, month: int, day: int) -> bool:
	return year >= 1 and month >= 1 and month <= 12 and day >= 1 and day <= days_in_month(year, month)


static func format_day(day_count: int) -> String:
	var date := day_to_date(day_count)
	return "%d %s %d" % [date["day"], month_name(date["month"]), date["year"]]


static func month_name(month: int) -> String:
	const MONTHS: Array[String] = [
		"", "January", "February", "March", "April", "May", "June",
		"July", "August", "September", "October", "November", "December",
	]
	return MONTHS[month] if month >= 1 and month <= 12 else "Invalid"


static func _compare_dates(
	year_a: int,
	month_a: int,
	day_a: int,
	year_b: int,
	month_b: int,
	day_b: int
) -> int:
	if year_a != year_b:
		return -1 if year_a < year_b else 1
	if month_a != month_b:
		return -1 if month_a < month_b else 1
	if day_a != day_b:
		return -1 if day_a < day_b else 1
	return 0
