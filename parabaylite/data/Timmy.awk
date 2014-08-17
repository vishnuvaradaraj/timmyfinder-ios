BEGIN { 
	FS = ",";
	OFS = ",";
}

{ 
	fc = split($5, a, "|");
	gsub(/Tim Hortons - /, "", $4);
	address = a[1];
	
	start=1;
	if (fc>3) {
		start = 2;	
	}
	address = a[start++];
	citystate=a[start++];
	cc = split(citystate, b, " ");
	ccstart = 1;		
	city = b[ccstart++]
	state = b[ccstart++]
	if (length(state) != 2) {
		city = city " " state;
		state = b[ccstart++];
	}
	if (length(state) != 2) {
		city = city " " state;
		state = b[ccstart++];
	}
	if (length(state) != 2) {
		city = city " " state;
		state = b[ccstart++];
	}

	zipcode = b[ccstart++]
	if (ccstart <= cc) {
		zipcode = zipcode b[ccstart++]
	}
	phone=a[start++];
	print "LOC"$1, $4, $2, $3, address, city,state, zipcode,"Timmy";
}

