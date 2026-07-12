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
	var ordinal := _date_ordinal(START_YEAR, START_MONTH, START_DAY) + maxi(day_count, 0)
	var year := START_YEAR + maxi(day_count, 0) / 365
	while _date_ordinal(year, 1, 1) > ordinal:
		year -= 1
	while _date_ordinal(year + 1, 1, 1) <= ordinal:
		year += 1
	var day_of_year := ordinal - _date_ordinal(year, 1, 1)
	var month := 1
	while day_of_year >= days_in_month(year, month):
		day_of_year -= days_in_month(year, month)
		month += 1
	return {"year": year, "month": month, "day": day_of_year + 1}


static func date_to_day(year: int, month: int, day: int) -> int:
	if not is_valid_date(year, month, day):
		return -1
	if _compare_dates(year, month, day, START_YEAR, START_MONTH, START_DAY) < 0:
		return -1
	return _date_ordinal(year, month, day) - _date_ordinal(START_YEAR, START_MONTH, START_DAY)


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


static func _date_ordinal(year: int, month: int, day: int) -> int:
	var previous_year := year - 1
	var result := previous_year * 365 + previous_year / 4 - previous_year / 100 + previous_year / 400
	for current_month in range(1, month):
		result += days_in_month(year, current_month)
	return result + day - 1
