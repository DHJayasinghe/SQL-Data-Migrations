SELECT
	P.PICKUP_ID PickupId,
	P.CUSTOMER_ID CustomerId,
	UPPER(TRIM(C.CUSTOMER_NAME)) CustomerName,
	CASE WHEN P.PICKUP_ADDRESS IS NULL THEN C.[ADDRESS] ELSE P.PICKUP_ADDRESS END Original_Address,
	(SELECT UPPER(STRING_AGG(T2.value,' ')) AS [Address] 
		FROM STRING_SPLIT((	
				SELECT REPLACE(
					--REPLACE(
					REPLACE(REPLACE(REPLACE(REPLACE(STRING_AGG(TRIM(REPLACE(REPLACE(T1.value,'SRI LANKA',''),'SRILANKA','')), ', ')
					,char(13), ' '),char(10), ' '), char(9), ' '),':',' ')
					--,'.','')
					,'_','/') AS [Address] --replace unnecessary tab spaces, line breaks(CR, LF CR+LF) with a space, colons, dots and replace underscore with forward slashes
				From STRING_SPLIT(CASE WHEN P.PICKUP_ADDRESS IS NULL THEN C.[ADDRESS] ELSE P.PICKUP_ADDRESS END,',') T1 --Split string by comma and concat words again with with a value
				WHERE TRIM(T1.value)!=''),' ') T2  --Split string by space and concat words again with with a value
		WHERE TRIM(T2.value)!='') [Cleared_Address],
	(SELECT UPPER(STRING_AGG(T2.value,' ')) AS [Address] 
		FROM STRING_SPLIT((	
				SELECT REPLACE(
					--REPLACE(
					REPLACE(REPLACE(REPLACE(REPLACE(STRING_AGG(TRIM(T1.value), ', ')
					,char(13), ' '),char(10), ' '), char(9), ' '),':','')
					--,'.','')
					,'_','/') AS [City] --replace unnecessary tab spaces, line breaks(CR, LF CR+LF) with a space, colons, dots and replace underscore with forward slashes
				From STRING_SPLIT(CASE WHEN P.PICKUP_TOWN IS NULL THEN C.TOWN ELSE P.PICKUP_TOWN END,',') T1 --Split string by comma and concat words again with with a value
				WHERE TRIM(T1.value)!=''),' ') T2  --Split string by space and concat words again with with a value
		WHERE TRIM(T2.value)!='') [City],
		C.CONTACTS Contacts
INTO #tmpPickupAddresses
FROM dbo.PICKUP P LEFT JOIN [dbo].[CUSTOMER] C
ON P.CUSTOMER_ID=C.CUSTOMER_ID

SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	REPLACE(REPLACE(CASE 
		WHEN PATINDEX('% COL %',Cleared_Address)>0 THEN STUFF(Cleared_Address,PATINDEX('% COL %',Cleared_Address),4,' COLOMBO') --ex: COL 03
		WHEN PATINDEX('% CO %',Cleared_Address)>0 THEN STUFF(Cleared_Address,PATINDEX('% CO %',Cleared_Address),3,' COLOMBO') --ex: CO 03
		WHEN PATINDEX('% COL-%',Cleared_Address)>0 THEN STUFF(Cleared_Address,PATINDEX('% COL-%',Cleared_Address),5,' COLOMBO ') --ex: COL-3
		WHEN PATINDEX('% COLOMBO-%',Cleared_Address)>0 THEN STUFF(Cleared_Address,PATINDEX('% COLOMBO-%',Cleared_Address),9,' COLOMBO ') --ex: COLOMBO-11
		WHEN PATINDEX('% COLOMB %',Cleared_Address)>0 THEN STUFF(Cleared_Address,PATINDEX('% COLOMB %',Cleared_Address),7,' COLOMBO ') --ex: COLOMB 11
		WHEN PATINDEX('% NO-[0-9]%',Cleared_Address)>0 THEN STUFF(Cleared_Address,PATINDEX('% NO-[0-9]%',Cleared_Address),4,' NO ') --ex: NO-479
		ELSE Cleared_Address END,'–',''),'"','')  Cleared_Address, --replace COL like keywords with COLOMBO
	City,
	Contacts
INTO #tmpPickupAddresses2
FROM #tmpPickupAddresses
DROP TABLE #tmpPickupAddresses --delete first temp table to release memory

SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	CONVERT(varchar(350),CASE WHEN CHARINDEX(REVERSE(City),REVERSE(Cleared_Address))>0 THEN REVERSE(TRIM(SUBSTRING(REVERSE(Cleared_Address),CHARINDEX(REVERSE(City),REVERSE(Cleared_Address)),LEN(Cleared_Address)))) ELSE Cleared_Address END) Cleared_Address, -- seperate contact details after city name on address field (REVERSE to search from end)
	CONVERT(varchar(350),CASE WHEN CHARINDEX(REVERSE(City),REVERSE(Cleared_Address))>0 THEN REVERSE(TRIM(REPLACE(SUBSTRING(REVERSE(Cleared_Address),0,CHARINDEX(REVERSE(City),REVERSE(Cleared_Address))),City,''))) ELSE '' END) Filtered_Contact,
	City,
	Contacts
INTO #tmpPickupAddresses3
FROM #tmpPickupAddresses2
DROP TABLE #tmpPickupAddresses2

;WITH STEP1 AS
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	CONCAT(Cleared_Address,CASE WHEN LEN(Filtered_Contact)<=2 AND ISNUMERIC(Filtered_Contact)=1 THEN CONCAT(' ',Filtered_Contact) ELSE '' END) Cleared_Address, --to transfer COLOMBO 03 like single char prefix back to the Address field while removing from contact field
	CASE WHEN LEN(Filtered_Contact)<=2 AND ISNUMERIC(TRIM(Filtered_Contact))=1 THEN '' ELSE TRIM(Filtered_Contact) END Filtered_Contact,
	City,
	Contacts
FROM #tmpPickupAddresses3)
SELECT
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	CONVERT(varchar(350),CASE 
		WHEN REPLACE(REPLACE(REPLACE(REPLACE(Filtered_Contact,'(',''),')',''),',',''),'.','') IN ('ROAD','RD','AVE','IPZ','AVENUE','NORTH','CENTRAL HOSPITAL','ZONE','WAREHOUSE','NORTH','SOUTH','WEST','FORT') OR (LEN(Filtered_Contact)<9 AND ISNUMERIC(Filtered_Contact)=1) THEN CONCAT(Cleared_Address,' ',Filtered_Contact) --move road, avenue like prefix back to address fields while removing from contact field
		WHEN LEN(REPLACE(REPLACE(Filtered_Contact,',',''),'.',''))<=3 THEN CONCAT(Cleared_Address,'',Filtered_Contact) 
		ELSE Cleared_Address 
	END) Cleared_Address,
	CASE 
		WHEN REPLACE(REPLACE(REPLACE(REPLACE(Filtered_Contact,'(',''),')',''),',',''),'.','') IN ('ROAD','RD','AVE','IPZ','AVENUE','NORTH','CENTRAL HOSPITAL','ZONE','WAREHOUSE','NORTH','SOUTH','WEST','FORT') OR (LEN(Filtered_Contact)<9 AND ISNUMERIC(Filtered_Contact)=1) THEN ''
		WHEN LEN(REPLACE(REPLACE(Filtered_Contact,',',''),'.',''))<=3 THEN '' 
		ELSE Filtered_Contact
	END Filtered_Contact,
	City,
	Contacts
INTO #tmpPickupAddresses4
FROM STEP1
DROP TABLE #tmpPickupAddresses3

;WITH STEP3 AS
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address, --remove duplicate words ex: '210 GALLE ROAD, COLOMBO 3, COLOMBO 3'
	REPLACE(REPLACE(REPLACE(REPLACE(Filtered_Contact,'(',''),')',''),',',''),'.','') Cleared_Contact, -- seperated contact details without unwanted characters
	Filtered_Contact,
	City,
	Contacts
FROM #tmpPickupAddresses4)
SELECT
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	IIF(SUBSTRING(REVERSE(Cleared_Address),1,1)='.',SUBSTRING(Cleared_Address,1,LEN(Cleared_Address)-1),Cleared_Address) Cleared_Address, --remove trailing dot if exists
	IIF(PATINDEX('%[0-9] [0-9]%',IIF(PATINDEX('%[0-9] [0-9]%',Cleared_Contact)>0,STUFF(Cleared_Contact,PATINDEX('%[0-9] [0-9]%',Cleared_Contact)+1,1,''),Cleared_Contact))>0, --step2 of clear phone numberes with spaces
		STUFF(IIF(PATINDEX('%[0-9] [0-9]%',Cleared_Contact)>0,STUFF(Cleared_Contact,PATINDEX('%[0-9] [0-9]%',Cleared_Contact)+1,1,''),Cleared_Contact),PATINDEX('%[0-9] [0-9]%',IIF(PATINDEX('%[0-9] [0-9]%',Cleared_Contact)>0,STUFF(Cleared_Contact,PATINDEX('%[0-9] [0-9]%',Cleared_Contact)+1,1,''),Cleared_Contact))+1,1,''),
		IIF(PATINDEX('%[0-9] [0-9]%',Cleared_Contact)>0,STUFF(Cleared_Contact,PATINDEX('%[0-9] [0-9]%',Cleared_Contact)+1,1,''),Cleared_Contact)) Cleared_Contact, --step1 of clear phone numberes with spaces
	Filtered_Contact,
	City,
	Contacts
INTO #tmpPickupAddresses5
FROM STEP3
DROP TABLE #tmpPickupAddresses4


;WITH STEP4 AS
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	IIF(PATINDEX('[0-9] OB%',REVERSE(Cleared_Address))>0,REVERSE(STUFF(REVERSE(Cleared_Address),PATINDEX('[0-9] OB%',REVERSE(Cleared_Address))+1,1,'0 ')),
		IIF(PATINDEX('[^0-9][0-9] OB%',REVERSE(Cleared_Address))>0,REVERSE(STUFF(REVERSE(Cleared_Address),PATINDEX('[^0-9][0-9] OB%',REVERSE(Cleared_Address))+1,1,'0 ')),Cleared_Address)) Cleared_Address, --fix COLOMBO 3 like city prefixes as COLOMBO 03
	Cleared_Contact,
	(SELECT COUNT(value) FROM STRING_SPLIT(Cleared_Contact,' ') WHERE TRIM(value) NOT IN ('',',','.','&','-','/')) NoOfWords,
	(SELECT COUNT(value) FROM STRING_SPLIT(Cleared_Contact,' ') 
		WHERE TRIM(value) NOT IN ('',',','.','&','-') 
		AND (TRIM(value) IN ('LOT''BLOCK','INDUSTRIAL','ZONE','BUILDING','FLOOR','HOUSE','DEPARTMENT','APARTMENT','FACTORY','FACTRY','ROAD','LANE','NORTH','SOUTH','WEST','NEW','TOWN','TOWER','CENTRAL','HOSPITAL','DIVISION','IMPORTS','EXPORTS','GARDINER','MAWATHA','EPZ','TRADE','PORUWADANDA','BORALUGODA','DEPARTMENT','AVIASSAWELLA','MINUWANGODA','PANOLUWA','TORAKOLAYAYA','MALVANA','PITTIYAGODA') --if contains this keywords
		OR (ISNUMERIC(value)=1 AND LEN(value)<=2) OR (LEN(value)<=3 AND PATINDEX('%[0-9]TH%',value)>0) --if contains keywords like 4th
		OR TRIM(value) IN (SELECT Distinct City From #tmpPickupAddresses5)) --if contains city word
	) NoOfPrefixWords,  
	Filtered_Contact,
	IIF(PATINDEX('% [0-9]',City)>0,STUFF(City,PATINDEX('% [0-9]',City),1,' 0'),City) City, --fix COLOMBO 3 like city address as COLOMBO 03
	Contacts
FROM #tmpPickupAddresses5)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	IIF(PATINDEX('%BO [0-9][^0-9]%',Cleared_Address)>0,STUFF(Cleared_Address,PATINDEX('%BO [0-9][^0-9]%',Cleared_Address)+2,1,' 0'),Cleared_Address) Cleared_Address, --fix COLOMBO 3 like city prefixes as COLOMBO 03 (search from begin -> if duplicate words exists)
	CASE WHEN 
		CASE NoOfWords WHEN 1 THEN 1 ELSE ROUND(CONVERT(decimal(8,0),CONVERT(decimal(8,1),NoOfWords)/2),0) END <= NoOfPrefixWords  -- if NoOfWords = 1 not divided by 2 
	THEN Filtered_Contact ELSE NULL END Seperated_Addr_Prefix, --if most number of words contains above keywords -> not contain contact details
	CASE WHEN 
		CASE NoOfWords WHEN 1 THEN 1 ELSE ROUND(CONVERT(decimal(8,0),CONVERT(decimal(8,1),NoOfWords)/2),0) END <= NoOfPrefixWords
	THEN NULL ELSE Filtered_Contact END Cleared_Addr_Contact,
	City AS Original_City, --fix COLOMBO 3 like city address as COLOMBO 03
	Contacts
INTO #tmpPickupAddresses6
FROM STEP4 T2
DROP TABLE #tmpPickupAddresses5

;WITH STEP5 AS 
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	REPLACE(REPLACE(Original_City,' ',''),'-','') Cleared_Original_City, --clear unwanted characters (spaces, dashes)
	CT.CityValue Cleared_City,
	Contacts,
	ROW_NUMBER() OVER(PARTITION BY PickupId ORDER BY PickupId) as rn --partition by Pickup ID -> rank by row number
FROM #tmpPickupAddresses6 T1 LEFT JOIN dbo.[__CityList] CT
ON DIFFERENCE(T1.Original_City,CT.CityKey)=4 AND CHARINDEX(REVERSE(CT.CityKey),REVERSE(REPLACE(REPLACE(T1.Original_City,' ',''),'-','')))>0 --search by city name, search from end 
)
SELECT
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address, 
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	IIF(PATINDEX('%[A-Z][0-9]',Cleared_Original_City)>0,SUBSTRING(Cleared_Original_City,0,PATINDEX('%[A-Z][0-9]',Cleared_Original_City)+1)+'0'+RIGHT(Cleared_Original_City,1),Cleared_Original_City) Cleared_Original_City,
	Cleared_City,
	Contacts
INTO #tmpPickupAddresses7
FROM STEP5
WHERE rn = 1
DROP TABLE #tmpPickupAddresses6


-- #######################################################
--seperate addresses with success clear city names matching result
;WITH STEP5_2 AS
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	IIF(CHARINDEX(ISNULL(Original_City,''),Cleared_Address)>0,REVERSE(STUFF(REVERSE(Cleared_Address),CHARINDEX(REVERSE(ISNULL(Original_City,'')),REVERSE(Cleared_Address)),LEN(Original_City),'')),
	IIF(CHARINDEX(ISNULL(Cleared_City,''),Cleared_Address)>0,REVERSE(STUFF(REVERSE(Cleared_Address),CHARINDEX(REVERSE(ISNULL(Cleared_City,'')),REVERSE(Cleared_Address)),LEN(Cleared_City),'')),
	Cleared_Address)) Cleared_Address, --remove original city (if exist) else remove cleared city (if exist) from address field after similar sounding city mapping
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	1 CityMatchIndex, --1 = mapped exactly | 0 = mapped by similar sounding names | -1 no matching, seperated as exist
	Contacts
FROM #tmpPickupAddresses7 WHERE Cleared_City IS NOT NULL)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	IIF(CHARINDEX(ISNULL(Original_City,''),Cleared_Address)>0,REVERSE(STUFF(REVERSE(Cleared_Address),CHARINDEX(REVERSE(ISNULL(Original_City,'')),REVERSE(Cleared_Address)),LEN(Original_City),'')),
	IIF(CHARINDEX(ISNULL(Cleared_City,''),Cleared_Address)>0,REVERSE(STUFF(REVERSE(Cleared_Address),CHARINDEX(REVERSE(ISNULL(Cleared_City,'')),REVERSE(Cleared_Address)),LEN(Cleared_City),'')),
	Cleared_Address)) Cleared_Address, --search remove city names for 2nd time (for duplicates -> if exist)
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex, --1 = mapped exactly | 0 = mapped by similar sounding names | -1 no matching, seperated as exist
	Contacts
INTO #tblClearedCityAddresses -- matching city pickup addresses
FROM STEP5_2


-- #######################################################
--match cities by similar sounding names for addresses with no clear city names matching result
;WITH STEP6 AS
(SELECT
	TblNoCity.Original_City,
	TblNoCity.Cleared_Original_City,
	CT.CityValue SimilarCity,
	dbo.WordSimilarity(CT.CityKey,TblNoCity.Cleared_Original_City,2) Similarity,
	dbo.WordsDiff(CT.CityKey,TblNoCity.Cleared_Original_City,2) Diff
FROM
(SELECT DISTINCT Original_City,Cleared_Original_City FROM #tmpPickupAddresses7 WHERE Cleared_City IS NULL) TblNoCity  --available minimum city length is 4, exclude rest
	INNER JOIN dbo.[__CityList] CT
ON DIFFERENCE(REVERSE(TblNoCity.Cleared_Original_City),REVERSE(CT.CityKey)) = 4 AND --similar sounding words (4 highly similar sounding)
	dbo.WordsDiff(CT.CityKey,TblNoCity.Cleared_Original_City,2) <= 3 --words different between 0 and 3
--ORDER BY TblNoCity.Original_City
),
STEP6_2 AS
(SELECT
	Original_City,
	SimilarCity,
	Similarity,
	Diff,
	ROW_NUMBER() OVER(PARTITION BY Original_City ORDER BY Original_City,Similarity DESC,Diff ASC) as rn
FROM STEP6)
SELECT 
	Original_City,
	SimilarCity,
	Similarity,
	Diff
INTO #similarCityNames
FROM STEP6_2
WHERE rn=1


-- #######################################################
-- addressess with similar sounding city names mapping
;WITH STEP6_3 AS
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	IIF(CHARINDEX(ISNULL(TblNoCity.Original_City,''),Cleared_Address)>0,REVERSE(STUFF(REVERSE(Cleared_Address),CHARINDEX(REVERSE(ISNULL(TblNoCity.Original_City,'')),REVERSE(Cleared_Address)),LEN(TblNoCity.Original_City),'')),
	IIF(CHARINDEX(ISNULL(TblMappedCities.SimilarCity,''),Cleared_Address)>0,REVERSE(STUFF(REVERSE(Cleared_Address),CHARINDEX(REVERSE(ISNULL(TblMappedCities.SimilarCity,'')),REVERSE(Cleared_Address)),LEN(TblMappedCities.SimilarCity),'')),
	Cleared_Address)) Cleared_Address, --remove original city (if exist) else remove cleared city (if exist) from address field after similar sounding city mapping
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	TblNoCity.Original_City,
	TblMappedCities.SimilarCity Cleared_City,
	0 CityMatchIndex,
	Contacts
FROM
(SELECT * FROM #tmpPickupAddresses7 WHERE Cleared_City IS NULL) TblNoCity INNER JOIN
(SELECT * FROM #similarCityNames
WHERE (Similarity-Diff)>1 --where similarity and difference is greater than 1
	AND Original_City NOT IN ('COLOMBO 16','COLOMB','COLOMBO','WATALA','COLOMBO RD NEGOMBO','KADANA','KANUWANA','NAWAM MW','WATHTHALA','WEERAKODIYANA')) TblMappedCities --manually exclude unmatching city names
ON TblNoCity.Original_City=TblMappedCities.Original_City)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	IIF(CHARINDEX(ISNULL(Original_City,''),Cleared_Address)>0,REVERSE(STUFF(REVERSE(Cleared_Address),CHARINDEX(REVERSE(ISNULL(Original_City,'')),REVERSE(Cleared_Address)),LEN(Original_City),'')),
	IIF(CHARINDEX(ISNULL(Cleared_City,''),Cleared_Address)>0,REVERSE(STUFF(REVERSE(Cleared_Address),CHARINDEX(REVERSE(ISNULL(Cleared_City,'')),REVERSE(Cleared_Address)),LEN(Cleared_City),'')),
	Cleared_Address)) Cleared_Address,  --search remove city names for 2nd time (for duplicates -> if exist)
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #tblMappedCityAddresses --Similar sounding city matching pickup addressess
FROM STEP6_3


-- rest of the addressess with no matching valid city names
;WITH STEP7 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	TRIM(IIF(CHARINDEX(',',Original_City)>0,REVERSE(SUBSTRING(REVERSE(Original_City),0,CHARINDEX(',',REVERSE(Original_City)))),Original_City)) Cleared_City,
	Contacts
FROM #tmpPickupAddresses7 
WHERE Cleared_City IS NULL 
AND PickupId NOT IN (SELECT PickupId FROM #tblMappedCityAddresses)),
STEP7_2 AS
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	IIF(CHARINDEX(ISNULL(Cleared_City,''),Cleared_Address)>0,REVERSE(STUFF(REVERSE(Cleared_Address),CHARINDEX(REVERSE(ISNULL(Cleared_City,'')),REVERSE(Cleared_Address)),LEN(Cleared_City),'')),Cleared_Address) Cleared_Address,
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	-1 CityMatchIndex,
	Contacts
FROM STEP7)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	IIF(CHARINDEX(ISNULL(Cleared_City,''),Cleared_Address)>0,REVERSE(STUFF(REVERSE(Cleared_Address),CHARINDEX(REVERSE(ISNULL(Cleared_City,'')),REVERSE(Cleared_Address)),LEN(Cleared_City),'')),Cleared_Address) Cleared_Address, --search remove city names for 2nd time (for duplicates -> if exist)
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #tblNoMatchCityAddresses -- no clear matching city pickup addressess
FROM STEP7_2

SELECT T1.* 
INTO #tmpPickupAddresses8 FROM
(SELECT * FROM #tblClearedCityAddresses -- CityMatchIndex = 1
UNION ALL
SELECT * FROM #tblMappedCityAddresses -- CityMatchIndex = 0
UNION ALL
SELECT * FROM #tblNoMatchCityAddresses) T1 -- CityMatchIndex = -1

-- release memory
DROP TABLE #tblClearedCityAddresses
DROP TABLE #similarCityNames 
DROP TABLE #tblMappedCityAddresses
DROP TABLE #tblNoMatchCityAddresses
DROP TABLE #tmpPickupAddresses7

-- ######################################################
-- clear Customer Name (if exists) at the begining of the address field
SELECT 
	PickupId,
	CustomerId,
	TRIM(CustomerName) CustomerName,
	Original_Address,
	CASE WHEN DIFFERENCE(CustomerName,Cleared_Address)>3 AND Cleared_Address LIKE CustomerName+'%' --where address fields contains customer name like leading words
		AND PATINDEX('%'+TRIM(CustomerName)+' CONTOURLINE%',Cleared_Address)=0  -- not contain certain words after => to avoid replacing address building values like "MAS ACTIVE CONTOURLINE" with customer name "MAS ACTIVE"
		AND PATINDEX('%'+TRIM(CustomerName)+' BUILDING%',Cleared_Address)=0 THEN 
		REPLACE(Cleared_Address,CustomerName,'') 
	ELSE Cleared_Address END Cleared_Address,
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #tmpPickupAddresses9
FROM #tmpPickupAddresses8
DROP TABLE #tmpPickupAddresses8

--seperate cleared_address field into prefixes, so can search for building terms
;WITH STEP8_1 AS
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	(SELECT STRING_AGG(TRIM([value]),', ') FROM STRING_SPLIT(CONCAT(Cleared_Address,' ',Seperated_Addr_Prefix),',') WHERE TRIM([value])!='') Cleared_Address, --remove trailing and leading commas
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #tmpPickupAddresses9),
STEP8_2 AS
(SELECT
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	(SELECT STRING_AGG(TRIM([value]),' ') FROM STRING_SPLIT(Cleared_Address,' ') WHERE TRIM([value])!='') Cleared_Address, --remove extra spaces
	REVERSE(SUBSTRING(REVERSE(Cleared_Address),1,CHARINDEX(',',REVERSE(Cleared_Address)))) Street, --Step4 - seperate comma seperated last set of words as street Street
	--TRIM(REPLACE(Cleared_Address,Street,'')) Cleared_Address,
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM STEP8_1),
STEP8_3 AS
(SELECT
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	--TRIM(REPLACE(Cleared_Address,Street,'')) Cleared_Address,
	(SELECT STRING_AGG(TRIM([value]),', ') FROM STRING_SPLIT(Street,',') WHERE TRIM([value])!='') Street, --Step4 - seperate comma seperated last set of words as street Street
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM STEP8_2)
,STEP8_4 AS(
SELECT
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	--Cleared_Address,
	TRIM(IIF(CHARINDEX(' ', Cleared_Address)>0,SUBSTRING(Cleared_Address,1,CHARINDEX(' ', Cleared_Address)),Cleared_Address)) Prefix1, -- seperate remain address field by spaces
	TRIM(IIF(CHARINDEX(' ', Cleared_Address)>0,STUFF(Cleared_Address,1,CHARINDEX(' ', Cleared_Address),''),NULL)) Prefix2,
	--TRIM(SUBSTRING(Cleared_Address,CHARINDEX(' ', Cleared_Address),LEN(Cleared_Address)+1)) Prefix2,
	Street, --Step4 - seperate comma seperated last set of words as street Street
	IIF(LEN(ISNULL(Street,''))>0,'Y','N') HasStreet,
	Seperated_Addr_Prefix,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM STEP8_3),
STEP8_5 AS
(SELECT
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Prefix1, 
	TRIM(IIF(CHARINDEX(' ', Prefix2)>0,SUBSTRING(Prefix2,1,CHARINDEX(' ', Prefix2)),Prefix2)) Prefix2,
	TRIM(IIF(CHARINDEX(' ', Prefix2)>0,STUFF(Prefix2,1,CHARINDEX(' ', Prefix2),''),NULL)) Prefix3,
	Street, 
	HasStreet,
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM STEP8_4)
,STEP8_6 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Prefix1,
	Prefix2,
	TRIM(IIF(CHARINDEX(' ', Prefix3)>0,SUBSTRING(Prefix3,1,CHARINDEX(' ', Prefix3)),Prefix3)) Prefix3,
	TRIM(IIF(CHARINDEX(' ', Prefix3)>0,STUFF(Prefix3,1,CHARINDEX(' ', Prefix3),''),NULL)) Prefix4,
	Street, 
	HasStreet,
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM STEP8_5)
,STEP8_7 AS
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Prefix1,
	Prefix2,
	Prefix3,
	TRIM(IIF(CHARINDEX(' ', Prefix4)>0,SUBSTRING(Prefix4,1,CHARINDEX(' ', Prefix4)),Prefix4)) Prefix4,
	TRIM(IIF(CHARINDEX(' ', Prefix4)>0,STUFF(Prefix4,1,CHARINDEX(' ', Prefix4),''),NULL)) Prefix5,
	Street, 
	HasStreet,
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM STEP8_6)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Prefix1,
	Prefix2,
	Prefix3,
	Prefix4,
	--(SELECT STRING_AGG([value],', ') FROM STRING_SPLIT(Prefix1,',') WHERE TRIM([value])!='') Prefix1, --remove leading and trailing commas (if exists)
	--(SELECT STRING_AGG([value],', ') FROM STRING_SPLIT(Prefix2,',') WHERE TRIM([value])!='') Prefix2, --remove leading and trailing commas (if exists)
	--(SELECT STRING_AGG([value],', ') FROM STRING_SPLIT(Prefix3,',') WHERE TRIM([value])!='') Prefix3, --remove leading and trailing commas (if exists)
	--(SELECT STRING_AGG([value],', ') FROM STRING_SPLIT(Prefix4,',') WHERE TRIM([value])!='') Prefix4, --remove leading and trailing commas (if exists)
	--(SELECT STRING_AGG([value],', ') FROM STRING_SPLIT(TRIM(IIF(CHARINDEX(' ', Prefix5)>0,SUBSTRING(Prefix5,1,CHARINDEX(' ', Prefix5)),Prefix5)),',') WHERE TRIM([value])!='') Prefix5,
	--(SELECT STRING_AGG([value],', ') FROM STRING_SPLIT(TRIM(IIF(CHARINDEX(' ', Prefix5)>0,STUFF(Prefix5,1,CHARINDEX(' ', Prefix5),''),NULL)),',') WHERE TRIM([value])!='') Prefix6,
	TRIM(IIF(CHARINDEX(' ', Prefix5)>0,SUBSTRING(Prefix5,1,CHARINDEX(' ', Prefix5)),Prefix5)) Prefix5,
	TRIM(IIF(CHARINDEX(' ', Prefix5)>0,STUFF(Prefix5,1,CHARINDEX(' ', Prefix5),''),NULL)) Prefix6,
	Street, 
	HasStreet,
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #tmpPickupAddresses10
FROM STEP8_7
DROP TABLE #tmpPickupAddresses9

--SELECT * FROM #tmpPickupAddresses10
--WHERE PickupId IN (10029,10038,10042,10029)

--Prefix match on 1 and 2 prefix columns
;WITH STEP9 AS(
SELECT *,
	'' AS Building,
	'' AS ToConcat,
	Prefix1 AS ToMatch1,
	Prefix2 AS ToMatch2
FROM #tmpPickupAddresses10)
,STEP9_1 AS
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	ToMatch1,
	ToMatch2,
	Prefix1, 
	Prefix2,
	Prefix3,
	Prefix4,
	Prefix5,
	Prefix6,
	--compare prefix1 column and prefix2 column
	IIF(
		((PATINDEX('[#/]',ToMatch1)>0 OR PATINDEX('NO%',ToMatch1)>0 OR CHARINDEX('LEVEL',ToMatch1)>0 OR PATINDEX('%[0-9]%',ToMatch1)>0 OR CHARINDEX('BLOCK',ToMatch1)>0 OR CHARINDEX('LOT',ToMatch1)>0 OR PATINDEX('APART%NT',ToMatch1)>0 OR LEN(TRIM(ISNULL(ToMatch1,'')))=0) AND ((PATINDEX('%[0-9]%[^HD]',ToMatch2)>0 OR PATINDEX('[0-9]',ToMatch2)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch2)>0) AND LEN(ISNULL(ToMatch2,'')) BETWEEN 0 AND 7)) --like "# 5" | "NO 5/2" | "LEVEL 4" | "3 1/1" | "LOT 4" | "BLOCK 12" | APARTMENT 602  AND Prefix2 is not a Tel# (max len=5) 
		OR (PATINDEX('%[0-9]%',ToMatch1)>0 AND (PATINDEX('%FL[OR]%',ToMatch2)>0 OR CHARINDEX('POST',ToMatch2)>0)) --like "7th FLOOR" | "07A POST"
		OR (PATINDEX('PO%',ToMatch1)>0 AND PATINDEX('BOX%',ToMatch2)>0),12,--like PO BOX
			IIF(PATINDEX('%[0-9]%',ToMatch1)>0,1,0)) PrefixMatch, 
	Street, 
	HasStreet,
	Seperated_Addr_Prefix,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM STEP9)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE PrefixMatch WHEN 12 THEN TRIM(CONCAT(ToMatch1,' ',ToMatch2)) WHEN 1 THEN ToMatch1 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(ToConcat,''),' ',ISNULL(CASE WHEN PrefixMatch IN (12,1) THEN NULL ELSE ToMatch1 END,''))) ToConcat, --building terms removed from prefix1 field and concat with cleared Prefix2
	TRIM(CASE PrefixMatch WHEN 12 THEN NULL ELSE ToMatch2 END) ToMatch1, --building terms removed from prefix2 field
	Prefix3 ToMatch2,
	--Prefix1, 
	--Prefix2,
	--Prefix3,
	Prefix4,
	Prefix5,
	Prefix6,
	Street, 
	HasStreet,
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #PrefixMatch_1_2
FROM STEP9_1
DROP TABLE #tmpPickupAddresses10
--SELECT * FROM #PrefixMatch_1_2 WHERE PickupId IN (11928)

--Prefix match on 2 and 3 prefix columns
;WITH STEP9_3 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	ToMatch1,
	ToMatch2,
	--Prefix1, 
	--Prefix2,
	--Prefix3,
	Prefix4,
	Prefix5,
	Prefix6,
	--compare prefix2 column and prefix3 column
	IIF(
		((PATINDEX('[#/]',ToMatch1)>0 OR PATINDEX('NO%',ToMatch1)>0 OR CHARINDEX('LEVEL',ToMatch1)>0 OR PATINDEX('%[0-9]%',ToMatch1)>0 OR CHARINDEX('BLOCK',ToMatch1)>0 OR CHARINDEX('LOT',ToMatch1)>0 OR PATINDEX('APART%NT',ToMatch1)>0 OR LEN(TRIM(ISNULL(ToMatch1,'')))=0) AND ((PATINDEX('%[0-9]%[^HD]',ToMatch2)>0 OR PATINDEX('[0-9]',ToMatch2)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch2)>0) AND LEN(ISNULL(ToMatch2,'')) BETWEEN 0 AND 7)) --like "NO 5/2" | "LEVEL 4" | "3 1/1" | "LOT 4" | "BLOCK 12" | "12" AND Prefix2 is not like 9TH or 2ND (Floor prefixes) and a Tel# (max len=5) 
		OR (PATINDEX('%[0-9]%',ToMatch1)>0 AND (PATINDEX('%FL[OR]%',ToMatch2)>0 OR CHARINDEX('POST',ToMatch2)>0)) --like "7th FLOOR" | "07A POST"
		OR (PATINDEX('PO%',ToMatch1)>0 AND PATINDEX('BOX%',ToMatch2)>0),12,--like PO BOX
			IIF((PATINDEX('%[0-9]%[^HDL]',ToMatch1)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch1)>0 OR PATINDEX('%[0-9]/%',ToMatch1)>0) AND LEN(REPLACE(ToMatch1,',','')) BETWEEN 3 AND 6,1,0)) PrefixMatch,
	Street, 
	HasStreet,
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #PrefixMatch_1_2)
--,STEP9_4 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE PrefixMatch WHEN 12 THEN TRIM(CONCAT(ToMatch1,' ',ToMatch2)) WHEN 1 THEN ToMatch1 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(ToConcat,''),' ',ISNULL(CASE WHEN PrefixMatch IN (12,1) THEN NULL ELSE ToMatch1 END,''))) ToConcat, --building terms removed from prefix2 field and concat with cleared Prefix2
	TRIM(CASE PrefixMatch WHEN 12 THEN NULL ELSE ToMatch2 END) ToMatch1, --building terms removed from prefix3 field
	Prefix4 ToMatch2,
	--Prefix1, 
	--Prefix2,
	--Prefix3,
	--Prefix4,
	Prefix5,
	Prefix6,
	Street, 
	HasStreet,
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #PrefixMatch_2_3
FROM STEP9_3
DROP TABLE #PrefixMatch_1_2
--SELECT * FROM #PrefixMatch_2_3 WHERE PickupId IN (11928)

--Prefix match on 3 and 4 prefix columns
;WITH STEP9_5 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	ToMatch1,
	ToMatch2,
	--Prefix1, 
	--Prefix2,
	--Prefix3,
	--Prefix4,
	Prefix5,
	Prefix6,
	--compare prefix3 column and prefix4 column
	IIF(
		((PATINDEX('[#/]',ToMatch1)>0 OR PATINDEX('NO%',ToMatch1)>0 OR CHARINDEX('LEVEL',ToMatch1)>0 OR PATINDEX('%[0-9]%',ToMatch1)>0 OR CHARINDEX('BLOCK',ToMatch1)>0 OR CHARINDEX('LOT',ToMatch1)>0 OR PATINDEX('APART%NT',ToMatch1)>0 OR LEN(TRIM(ISNULL(ToMatch1,'')))=0) AND ((PATINDEX('%[0-9]%[^HD]',ToMatch2)>0 OR PATINDEX('[0-9]',ToMatch2)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch2)>0) AND LEN(ISNULL(ToMatch2,'')) BETWEEN 0 AND 7)) --like "NO 5/2" | "LEVEL 4" | "3 1/1" | "LOT 4" | "BLOCK 12" | "12" AND Prefix2 is not a Tel# (max len=5) 
		OR (PATINDEX('%[0-9]%',ToMatch1)>0 AND (PATINDEX('%FL[OR]%',ToMatch2)>0 OR CHARINDEX('POST',ToMatch2)>0)) --like "7th FLOOR" | "07A POST"
		OR (PATINDEX('PO%',ToMatch1)>0 AND PATINDEX('BOX%',ToMatch2)>0),12,--like PO BOX
			IIF((PATINDEX('%[0-9]%[^HDL]',ToMatch1)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch1)>0 OR PATINDEX('%[0-9]/%',ToMatch1)>0) AND LEN(REPLACE(ToMatch1,',','')) BETWEEN 3 AND 6,1,0)) PrefixMatch,
	Street, 
	HasStreet,
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #PrefixMatch_2_3)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE PrefixMatch WHEN 12 THEN TRIM(CONCAT(ToMatch1,' ',ToMatch2)) WHEN 1 THEN ToMatch1 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(ToConcat,''),' ',ISNULL(CASE WHEN PrefixMatch IN (12,1) THEN NULL ELSE ToMatch1 END,''))) ToConcat, --building terms removed from prefix3 field and concat with cleared Prefix2
	TRIM(CASE PrefixMatch WHEN 12 THEN NULL ELSE ToMatch2 END) ToMatch1, --building terms removed from prefix4 field
	Prefix5 ToMatch2,
	--Prefix1, 
	--Prefix2,
	--Prefix3,
	--Prefix4,
	--Prefix5,
	Prefix6,
	Street, 
	HasStreet,
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #PrefixMatch_3_4 --save to memory simplify query expression table
FROM STEP9_5
DROP TABLE #PrefixMatch_2_3
--SELECT * FROM #PrefixMatch_3_4 WHERE PickupId IN (11928)

--Prefix match on 4 and 5 prefix columns
;WITH STEP9_7 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	CASE WHEN ToConcat IN ('ROAD','ESTATE') THEN CONCAT(Cleared_City,' ',ToConcat) ELSE ToConcat END ToConcat, --fix truncated road names during city name removal from address at begining, Ex: Original=>286A RAJAGIRIYA ROAD, RAJAGIRIYA | Cleared=>286A ROAD | AfterFix=>286A RAJAGIRIYA ROAD  / HANWELLA ESTATE
	ToMatch1, 
	ToMatch2,
	--Prefix1, 
	--Prefix2,
	--Prefix3,
	--Prefix4,
	--Prefix5,
	Prefix6,
	--compare prefix4 column and prefix5 column
	IIF(
		((PATINDEX('[#/]',ToMatch1)>0 OR PATINDEX('NO%',ToMatch1)>0 OR CHARINDEX('LEVEL',ToMatch1)>0 OR PATINDEX('%[0-9]%',ToMatch1)>0 OR CHARINDEX('BLOCK',ToMatch1)>0 OR CHARINDEX('LOT',ToMatch1)>0 OR PATINDEX('APART%NT',ToMatch1)>0 OR LEN(TRIM(ISNULL(ToMatch1,'')))=0) AND ((PATINDEX('%[0-9]%[^HD]',ToMatch2)>0 OR PATINDEX('[0-9]',ToMatch2)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch2)>0) AND LEN(ISNULL(ToMatch2,'')) BETWEEN 0 AND 7))
		OR (PATINDEX('%[0-9]%',ToMatch1)>0 AND (PATINDEX('%FL[OR]%',ToMatch2)>0 OR CHARINDEX('POST',ToMatch2)>0)) 
		OR (PATINDEX('PO%',ToMatch1)>0 AND PATINDEX('BOX%',ToMatch2)>0),12,
			IIF((PATINDEX('%[0-9]%[^HDL]',ToMatch1)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch1)>0 OR PATINDEX('%[0-9]/%',ToMatch1)>0) AND LEN(REPLACE(ToMatch1,',','')) BETWEEN 3 AND 6,1,0)) PrefixMatch,
	Street, 
	HasStreet,
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #PrefixMatch_3_4)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE PrefixMatch WHEN 12 THEN TRIM(CONCAT(ToMatch1,' ',ToMatch2)) WHEN 1 THEN ToMatch1 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(ToConcat,''),' ',ISNULL(CASE WHEN PrefixMatch IN (12,1) THEN NULL ELSE ToMatch1 END,''))) ToConcat, --building terms removed from prefix3 field and concat with cleared Prefix2
	TRIM(CASE PrefixMatch WHEN 12 THEN NULL ELSE ToMatch2 END) ToMatch1, --building terms removed from prefix4 field
	Prefix6 ToMatch2,
	--TRIM(CONCAT(ISNULL(Prefix6,''),' ',TRIM(CONCAT(ISNULL(Street,''),' ',Seperated_Addr_Prefix)))) ToMatch2, --move street field and seperated_addr_prefix field to prefix6 for filter
	--Prefix1, 
	--Prefix2,
	--Prefix3,
	--Prefix4,
	--Prefix5,
	--Prefix6,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #PrefixMatch_4_5
FROM STEP9_7
DROP TABLE #PrefixMatch_3_4
--SELECT * FROM #PrefixMatch_4_5 WHERE PickupId IN (11928)

--seperate prefix6 into further more prefixes, to search for remain building terms(if exists)
;WITH SETP10_1 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	ToMatch1,
	TRIM(IIF(CHARINDEX(' ', ToMatch2)>0,SUBSTRING(ToMatch2,1,CHARINDEX(' ', ToMatch2)),ToMatch2)) Prefix6, -- seperate remain address field by spaces
	TRIM(IIF(CHARINDEX(' ', ToMatch2)>0,STUFF(ToMatch2,1,CHARINDEX(' ', ToMatch2),''),NULL)) Prefix7,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #PrefixMatch_4_5)
,SETP10_2 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	ToMatch1,
	Prefix6,
	TRIM(IIF(CHARINDEX(' ', Prefix7)>0,SUBSTRING(Prefix7,1,CHARINDEX(' ', Prefix7)),Prefix7)) Prefix7, -- seperate remain address field by spaces
	TRIM(IIF(CHARINDEX(' ', Prefix7)>0,STUFF(Prefix7,1,CHARINDEX(' ', Prefix7),''),NULL)) Prefix8,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM SETP10_1)
,SETP10_3 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	ToMatch1,
	Prefix6,
	Prefix7,
	TRIM(IIF(CHARINDEX(' ', Prefix8)>0,SUBSTRING(Prefix8,1,CHARINDEX(' ', Prefix8)),Prefix8)) Prefix8, -- seperate remain address field by spaces
	TRIM(IIF(CHARINDEX(' ', Prefix8)>0,STUFF(Prefix8,1,CHARINDEX(' ', Prefix8),''),NULL)) Prefix9,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM SETP10_2)
,SETP10_4 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	ToMatch1,
	Prefix6,
	Prefix7,
	Prefix8,
	TRIM(IIF(CHARINDEX(' ', Prefix9)>0,SUBSTRING(Prefix9,1,CHARINDEX(' ', Prefix9)),Prefix9)) Prefix9, -- seperate remain address field by spaces
	TRIM(IIF(CHARINDEX(' ', Prefix9)>0,STUFF(Prefix9,1,CHARINDEX(' ', Prefix9),''),NULL)) Prefix10,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM SETP10_3)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	ToMatch1,
	Prefix6 AS ToMatch2,
	--Prefix6,
	Prefix7,
	Prefix8,
	Prefix9,
	TRIM(IIF(CHARINDEX(' ', Prefix10)>0,SUBSTRING(Prefix10,1,CHARINDEX(' ', Prefix10)),Prefix10)) Prefix10, -- seperate remain address field by spaces
	TRIM(IIF(CHARINDEX(' ', Prefix10)>0,STUFF(Prefix10,1,CHARINDEX(' ', Prefix10),''),NULL)) Prefix11,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #tmpPickupAddresses13
FROM SETP10_4
DROP TABLE #PrefixMatch_4_5

--Prefix match on 5 and 6 prefix columns
;WITH STEP11_1 AS
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	ToMatch1, 
	ToMatch2,
	--Prefix6,
	Prefix7,
	Prefix8,
	Prefix9,
	Prefix10,
	Prefix11,
	IIF(
		((PATINDEX('[#/]',ToMatch1)>0 OR PATINDEX('NO%',ToMatch1)>0 OR CHARINDEX('LEVEL',ToMatch1)>0 OR PATINDEX('%[0-9]%',ToMatch1)>0 OR CHARINDEX('BLOCK',ToMatch1)>0 OR CHARINDEX('LOT',ToMatch1)>0 OR PATINDEX('APART%NT',ToMatch1)>0 OR LEN(TRIM(ISNULL(ToMatch1,'')))=0) AND ((PATINDEX('%[0-9]%[^HD]',ToMatch2)>0 OR PATINDEX('[0-9]',ToMatch2)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch2)>0) AND LEN(ISNULL(ToMatch2,'')) BETWEEN 0 AND 7))
		OR (PATINDEX('%[0-9]%',ToMatch1)>0 AND (PATINDEX('%FL[OR]%',ToMatch2)>0 OR CHARINDEX('POST',ToMatch2)>0)) 
		OR (PATINDEX('PO%',ToMatch1)>0 AND PATINDEX('BOX%',ToMatch2)>0),12,
			IIF((PATINDEX('%[0-9]%[^HDL]',ToMatch1)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch1)>0 OR PATINDEX('%[0-9]/%',ToMatch1)>0) AND LEN(REPLACE(ToMatch1,',','')) BETWEEN 3 AND 6,1,0)) PrefixMatch,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #tmpPickupAddresses13)
--,STEP11_2 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE PrefixMatch WHEN 12 THEN TRIM(CONCAT(ToMatch1,' ',ToMatch2)) WHEN 1 THEN ToMatch1 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(ToConcat,''),' ',ISNULL(CASE WHEN PrefixMatch IN (12,1) THEN NULL ELSE ToMatch1 END,''))) ToConcat, --building terms removed from prefix3 field and concat with cleared Prefix2
	TRIM(CASE PrefixMatch WHEN 12 THEN NULL ELSE ToMatch2 END) ToMatch1, --building terms removed from prefix4 field
	Prefix7 ToMatch2,
	--Prefix6,
	--Prefix7,
	Prefix8,
	Prefix9,
	Prefix10,
	Prefix11,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #PrefixMatch_5_6
FROM STEP11_1
DROP TABLE #tmpPickupAddresses13

--Prefix match on 6 and 7 prefix columns
;WITH STEP11_3 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	ToMatch1, 
	ToMatch2,
	--Prefix6,
	--Prefix7,
	Prefix8,
	Prefix9,
	Prefix10,
	Prefix11,
	IIF(
		((PATINDEX('[#/]',ToMatch1)>0 OR PATINDEX('NO%',ToMatch1)>0 OR CHARINDEX('LEVEL',ToMatch1)>0 OR PATINDEX('%[0-9]%',ToMatch1)>0 OR CHARINDEX('BLOCK',ToMatch1)>0 OR CHARINDEX('LOT',ToMatch1)>0 OR PATINDEX('APART%NT',ToMatch1)>0 OR LEN(TRIM(ISNULL(ToMatch1,'')))=0) AND ((PATINDEX('%[0-9]%[^HD]',ToMatch2)>0 OR PATINDEX('[0-9]',ToMatch2)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch2)>0) AND LEN(ISNULL(ToMatch2,'')) BETWEEN 0 AND 7))
		OR (PATINDEX('%[0-9]%',ToMatch1)>0 AND (PATINDEX('%FL[OR]%',ToMatch2)>0 OR CHARINDEX('POST',ToMatch2)>0)) 
		OR (PATINDEX('PO%',ToMatch1)>0 AND PATINDEX('BOX%',ToMatch2)>0),12,
			IIF((PATINDEX('%[0-9]%[^HDL]',ToMatch1)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch1)>0 OR PATINDEX('%[0-9]/%',ToMatch1)>0) AND LEN(REPLACE(ToMatch1,',','')) BETWEEN 3 AND 6,1,0)) PrefixMatch,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #PrefixMatch_5_6)
--,STEP11_4 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE PrefixMatch WHEN 12 THEN TRIM(CONCAT(ToMatch1,' ',ToMatch2)) WHEN 1 THEN ToMatch1 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(ToConcat,''),' ',ISNULL(CASE WHEN PrefixMatch IN (12,1) THEN NULL ELSE ToMatch1 END,''))) ToConcat, --building terms removed from prefix3 field and concat with cleared Prefix2
	TRIM(CASE PrefixMatch WHEN 12 THEN NULL ELSE ToMatch2 END) ToMatch1, --building terms removed from prefix4 field
	Prefix8 ToMatch2,
	--Prefix6,
	--Prefix7,
	--Prefix8,
	Prefix9,
	Prefix10,
	Prefix11,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #PrefixMatch_6_7
FROM STEP11_3
DROP TABLE #PrefixMatch_5_6

--Prefix match on 7 and 8 prefix columns
;WITH STEP11_5 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	ToMatch1, 
	ToMatch2,
	--Prefix6,
	--Prefix7,
	--Prefix8,
	Prefix9,
	Prefix10,
	Prefix11,
	IIF(
		((PATINDEX('[#/]',ToMatch1)>0 OR PATINDEX('NO%',ToMatch1)>0 OR CHARINDEX('LEVEL',ToMatch1)>0 OR PATINDEX('%[0-9]%',ToMatch1)>0 OR CHARINDEX('BLOCK',ToMatch1)>0 OR CHARINDEX('LOT',ToMatch1)>0 OR PATINDEX('APART%NT',ToMatch1)>0 OR LEN(TRIM(ISNULL(ToMatch1,'')))=0) AND ((PATINDEX('%[0-9]%[^HD]',ToMatch2)>0 OR PATINDEX('[0-9]',ToMatch2)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch2)>0) AND LEN(ISNULL(ToMatch2,'')) BETWEEN 0 AND 7))
		OR (PATINDEX('%[0-9]%',ToMatch1)>0 AND (PATINDEX('%FL[OR]%',ToMatch2)>0 OR CHARINDEX('POST',ToMatch2)>0)) 
		OR (PATINDEX('PO%',ToMatch1)>0 AND PATINDEX('BOX%',ToMatch2)>0),12,
			IIF((PATINDEX('%[0-9]%[^HDL]',ToMatch1)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch1)>0 OR PATINDEX('%[0-9]/%',ToMatch1)>0) AND LEN(REPLACE(ToMatch1,',','')) BETWEEN 3 AND 6,1,0)) PrefixMatch,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #PrefixMatch_6_7)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE PrefixMatch WHEN 12 THEN TRIM(CONCAT(ToMatch1,' ',ToMatch2)) WHEN 1 THEN ToMatch1 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(ToConcat,''),' ',ISNULL(CASE WHEN PrefixMatch IN (12,1) THEN NULL ELSE ToMatch1 END,''))) ToConcat, --building terms removed from prefix3 field and concat with cleared Prefix2
	TRIM(CASE PrefixMatch WHEN 12 THEN NULL ELSE ToMatch2 END) ToMatch1, --building terms removed from prefix4 field
	Prefix9 ToMatch2,
	--Prefix6,
	--Prefix7,
	--Prefix8,
	--Prefix9,
	Prefix10,
	Prefix11,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #PrefixMatch_7_8
FROM STEP11_5
DROP TABLE #PrefixMatch_6_7

--Prefix match on 8 and 9 prefix columns
;WITH STEP11_7 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	ToMatch1, 
	ToMatch2,
	--Prefix6,
	--Prefix7,
	--Prefix8,
	--Prefix9,
	Prefix10,
	Prefix11,
	IIF(
		((PATINDEX('[#/]',ToMatch1)>0 OR PATINDEX('NO%',ToMatch1)>0 OR CHARINDEX('LEVEL',ToMatch1)>0 OR PATINDEX('%[0-9]%',ToMatch1)>0 OR CHARINDEX('BLOCK',ToMatch1)>0 OR CHARINDEX('LOT',ToMatch1)>0 OR PATINDEX('APART%NT',ToMatch1)>0 OR LEN(TRIM(ISNULL(ToMatch1,'')))=0) AND ((PATINDEX('%[0-9]%[^HD]',ToMatch2)>0 OR PATINDEX('[0-9]',ToMatch2)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch2)>0) AND LEN(ISNULL(ToMatch2,'')) BETWEEN 0 AND 7))
		OR (PATINDEX('%[0-9]%',ToMatch1)>0 AND (PATINDEX('%FL[OR]%',ToMatch2)>0 OR CHARINDEX('POST',ToMatch2)>0)) 
		OR (PATINDEX('PO%',ToMatch1)>0 AND PATINDEX('BOX%',ToMatch2)>0),12,
			IIF((PATINDEX('%[0-9]%[^HDL]',ToMatch1)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch1)>0 OR PATINDEX('%[0-9]/%',ToMatch1)>0) AND LEN(REPLACE(ToMatch1,',','')) BETWEEN 3 AND 6,1,0)) PrefixMatch,--88A | 88, | 141/9
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #PrefixMatch_7_8)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE PrefixMatch WHEN 12 THEN TRIM(CONCAT(ToMatch1,' ',ToMatch2)) WHEN 1 THEN ToMatch1 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(ToConcat,''),' ',ISNULL(CASE WHEN PrefixMatch IN (12,1) THEN NULL ELSE ToMatch1 END,''))) ToConcat, --building terms removed from prefix3 field and concat with cleared Prefix2
	TRIM(CASE PrefixMatch WHEN 12 THEN NULL ELSE ToMatch2 END) ToMatch1, --building terms removed from prefix4 field
	Prefix10 ToMatch2,
	--Prefix6,
	--Prefix7,
	--Prefix8,
	--Prefix9,
	--Prefix10,
	Prefix11,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #PrefixMatch_8_9
FROM STEP11_7
DROP TABLE #PrefixMatch_7_8

--Prefix match on 9 and 10 prefix columns
;WITH STEP11_9 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	ToMatch1, 
	ToMatch2,
	--Prefix6,
	--Prefix7,
	--Prefix8,
	--Prefix9,
	--Prefix10,
	Prefix11,
	IIF(
		((PATINDEX('[#/]',ToMatch1)>0 OR PATINDEX('NO%',ToMatch1)>0 OR CHARINDEX('LEVEL',ToMatch1)>0 OR PATINDEX('%[0-9]%',ToMatch1)>0 OR CHARINDEX('BLOCK',ToMatch1)>0 OR CHARINDEX('LOT',ToMatch1)>0 OR PATINDEX('APART%NT',ToMatch1)>0 OR LEN(TRIM(ISNULL(ToMatch1,'')))=0) AND ((PATINDEX('%[0-9]%[^HD]',ToMatch2)>0 OR PATINDEX('[0-9]',ToMatch2)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch2)>0) AND LEN(ISNULL(ToMatch2,'')) BETWEEN 0 AND 7))
		OR (PATINDEX('%[0-9]%',ToMatch1)>0 AND (PATINDEX('%FL[OR]%',ToMatch2)>0 OR CHARINDEX('POST',ToMatch2)>0)) 
		OR (PATINDEX('PO%',ToMatch1)>0 AND PATINDEX('BOX%',ToMatch2)>0),12,
			IIF((PATINDEX('%[0-9]%[^HDL]',ToMatch1)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch1)>0 OR PATINDEX('%[0-9]/%',ToMatch1)>0) AND LEN(REPLACE(ToMatch1,',','')) BETWEEN 3 AND 6,1,0)) PrefixMatch,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #PrefixMatch_8_9)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE PrefixMatch WHEN 12 THEN TRIM(CONCAT(ToMatch1,' ',ToMatch2)) WHEN 1 THEN ToMatch1 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(ToConcat,''),' ',ISNULL(CASE WHEN PrefixMatch IN (12,1) THEN NULL ELSE ToMatch1 END,''))) ToConcat, --building terms removed from prefix3 field and concat with cleared Prefix2
	TRIM(CASE PrefixMatch WHEN 12 THEN NULL ELSE ToMatch2 END) ToMatch1, --building terms removed from prefix4 field
	Prefix11 ToMatch2,
	--Prefix6,
	--Prefix7,
	--Prefix8,
	--Prefix9,
	--Prefix10,
	--Prefix11,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #PrefixMatch_9_10
FROM STEP11_9
DROP TABLE #PrefixMatch_8_9

--Prefix match on 10 and 11 prefix columns
;WITH STEP11_11 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	ToMatch1, 
	ToMatch2,
	--Prefix6,
	--Prefix7,
	--Prefix8,
	--Prefix9,
	--Prefix10,
	--Prefix11,
	IIF(
		((PATINDEX('[#/]',ToMatch1)>0 OR PATINDEX('NO%',ToMatch1)>0 OR CHARINDEX('LEVEL',ToMatch1)>0 OR PATINDEX('%[0-9]%',ToMatch1)>0 OR CHARINDEX('BLOCK',ToMatch1)>0 OR CHARINDEX('LOT',ToMatch1)>0 OR PATINDEX('APART%NT',ToMatch1)>0 OR LEN(TRIM(ISNULL(ToMatch1,'')))=0) AND ((PATINDEX('%[0-9]%[^HD]',ToMatch2)>0 OR PATINDEX('[0-9]',ToMatch2)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch2)>0) AND LEN(ISNULL(ToMatch2,'')) BETWEEN 0 AND 7))
		OR (PATINDEX('%[0-9]%',ToMatch1)>0 AND (PATINDEX('%FL[OR]%',ToMatch2)>0 OR CHARINDEX('POST',ToMatch2)>0)) 
		OR (PATINDEX('PO%',ToMatch1)>0 AND PATINDEX('BOX%',ToMatch2)>0),12,
			IIF((PATINDEX('%[0-9]%[^HDL]',ToMatch1)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch1)>0 OR PATINDEX('%[0-9]/%',ToMatch1)>0) AND LEN(REPLACE(ToMatch1,',','')) BETWEEN 3 AND 6,1,0)) PrefixMatch,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #PrefixMatch_9_10)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE PrefixMatch WHEN 12 THEN TRIM(CONCAT(ToMatch1,' ',ToMatch2)) WHEN 1 THEN ToMatch1 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(ToConcat,''),' ',ISNULL(CASE WHEN PrefixMatch IN (12,1) THEN NULL ELSE ToMatch1 END,''))) ToConcat, --building terms removed from prefix3 field and concat with cleared Prefix2
	TRIM(CASE PrefixMatch WHEN 12 THEN NULL ELSE ToMatch2 END) ToMatch1, --building terms removed from prefix4 field
	--Prefix6,
	--Prefix7,
	--Prefix8,
	--Prefix9,
	--Prefix10,
	--Prefix11,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #PrefixMatch_10_11
FROM STEP11_11
DROP TABLE #PrefixMatch_9_10

--Prefix11 column further more seperation, to search for remain building terms(if exists)
;WITH SETP12_1 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	TRIM(IIF(CHARINDEX(' ', ToMatch1)>0,SUBSTRING(ToMatch1,1,CHARINDEX(' ', ToMatch1)),ToMatch1)) Prefix11, -- seperate remain address field by spaces
	TRIM(IIF(CHARINDEX(' ', ToMatch1)>0,STUFF(ToMatch1,1,CHARINDEX(' ', ToMatch1),''),NULL)) Prefix12,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #PrefixMatch_10_11)
,SETP12_2 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	Prefix11,
	TRIM(IIF(CHARINDEX(' ', Prefix12)>0,SUBSTRING(Prefix12,1,CHARINDEX(' ', Prefix12)),Prefix12)) Prefix12, -- seperate remain address field by spaces
	TRIM(IIF(CHARINDEX(' ', Prefix12)>0,STUFF(Prefix12,1,CHARINDEX(' ', Prefix12),''),NULL)) Prefix13,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM SETP12_1)
,SETP12_3 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	Prefix11,
	Prefix12,
	TRIM(IIF(CHARINDEX(' ', Prefix13)>0,SUBSTRING(Prefix13,1,CHARINDEX(' ', Prefix13)),Prefix13)) Prefix13, -- seperate remain address field by spaces
	TRIM(IIF(CHARINDEX(' ', Prefix13)>0,STUFF(Prefix13,1,CHARINDEX(' ', Prefix13),''),NULL)) Prefix14,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM SETP12_2)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	Prefix11 AS ToMatch1,
	Prefix12 AS ToMatch2,
	Prefix13,
	TRIM(IIF(CHARINDEX(' ', Prefix14)>0,SUBSTRING(Prefix14,1,CHARINDEX(' ', Prefix14)),Prefix14)) Prefix14, -- seperate remain address field by spaces
	TRIM(IIF(CHARINDEX(' ', Prefix14)>0,STUFF(Prefix14,1,CHARINDEX(' ', Prefix14),''),NULL)) Prefix15,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #tmpPickupAddresses18
FROM SETP12_3
DROP TABLE #PrefixMatch_10_11

--Prefix match on 11 and 12 prefix columns
;WITH STEP12_1 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	ToMatch1,
	ToMatch2,
	Prefix13,
	Prefix14,
	Prefix15,
	IIF(
		((PATINDEX('[#/]',ToMatch1)>0 OR PATINDEX('NO%',ToMatch1)>0 OR CHARINDEX('LEVEL',ToMatch1)>0 OR PATINDEX('%[0-9]%',ToMatch1)>0 OR CHARINDEX('BLOCK',ToMatch1)>0 OR CHARINDEX('LOT',ToMatch1)>0 OR PATINDEX('APART%NT',ToMatch1)>0 OR LEN(TRIM(ISNULL(ToMatch1,'')))=0) AND ((PATINDEX('%[0-9]%[^HD]',ToMatch2)>0 OR PATINDEX('[0-9]',ToMatch2)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch2)>0) AND LEN(ISNULL(ToMatch2,'')) BETWEEN 0 AND 7))
		OR (PATINDEX('%[0-9]%',ToMatch1)>0 AND (PATINDEX('%FL[OR]%',ToMatch2)>0 OR CHARINDEX('POST',ToMatch2)>0)) 
		OR (PATINDEX('PO%',ToMatch1)>0 AND PATINDEX('BOX%',ToMatch2)>0),12,
			IIF((PATINDEX('%[0-9]%[^HDL]',ToMatch1)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch1)>0 OR PATINDEX('%[0-9]/%',ToMatch1)>0) AND LEN(REPLACE(ToMatch1,',','')) BETWEEN 3 AND 6,1,0)) PrefixMatch,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #tmpPickupAddresses18)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE PrefixMatch WHEN 12 THEN TRIM(CONCAT(ToMatch1,' ',ToMatch2)) WHEN 1 THEN ToMatch1 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(ToConcat,''),' ',ISNULL(CASE WHEN PrefixMatch IN (12,1) THEN NULL ELSE ToMatch1 END,''))) ToConcat, --building terms removed from prefix3 field and concat with cleared Prefix2
	TRIM(CASE PrefixMatch WHEN 12 THEN NULL ELSE ToMatch2 END) ToMatch1, --building terms removed from prefix4 field
	Prefix13 ToMatch2,
	--Prefix13,
	Prefix14,
	Prefix15,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #PrefixMatch_11_12
FROM STEP12_1
DROP TABLE #tmpPickupAddresses18

--Prefix match on 12 and 13 prefix columns
;WITH STEP12_3 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	ToMatch1,
	ToMatch2,
	--Prefix13,
	Prefix14,
	Prefix15,
	IIF(
		((PATINDEX('[#/]',ToMatch1)>0 OR PATINDEX('NO%',ToMatch1)>0 OR CHARINDEX('LEVEL',ToMatch1)>0 OR PATINDEX('%[0-9]%',ToMatch1)>0 OR CHARINDEX('BLOCK',ToMatch1)>0 OR CHARINDEX('LOT',ToMatch1)>0 OR PATINDEX('APART%NT',ToMatch1)>0 OR LEN(TRIM(ISNULL(ToMatch1,'')))=0) AND ((PATINDEX('%[0-9]%[^HD]',ToMatch2)>0 OR PATINDEX('[0-9]',ToMatch2)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch2)>0) AND LEN(ISNULL(ToMatch2,'')) BETWEEN 0 AND 7)) 
		OR (PATINDEX('%[0-9]%',ToMatch1)>0 AND (PATINDEX('%FL[OR]%',ToMatch2)>0 OR CHARINDEX('POST',ToMatch2)>0)) 
		OR (PATINDEX('PO%',ToMatch1)>0 AND PATINDEX('BOX%',ToMatch2)>0),12, 
			IIF((PATINDEX('%[0-9]%[^HDL]',ToMatch1)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch1)>0 OR PATINDEX('%[0-9]/%',ToMatch1)>0) AND LEN(REPLACE(ToMatch1,',','')) BETWEEN 3 AND 6,1,0)) PrefixMatch,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #PrefixMatch_11_12
)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE PrefixMatch WHEN 12 THEN TRIM(CONCAT(ToMatch1,' ',ToMatch2)) WHEN 1 THEN ToMatch1 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(ToConcat,''),' ',ISNULL(CASE WHEN PrefixMatch IN (12,1) THEN NULL ELSE ToMatch1 END,''))) ToConcat, --building terms removed from prefix3 field and concat with cleared Prefix2
	TRIM(CASE PrefixMatch WHEN 12 THEN NULL ELSE ToMatch2 END) ToMatch1, --building terms removed from prefix4 field
	Prefix14 ToMatch2,
	--Prefix13,
	--Prefix14,
	Prefix15,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #PrefixMatch_12_13
FROM STEP12_3
DROP TABLE #PrefixMatch_11_12

--Prefix match on 13 and 14 prefix columns
;WITH STEP12_5 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	ToMatch1,
	ToMatch2,
	--Prefix13,
	--Prefix14,
	Prefix15,
	IIF(
		((PATINDEX('[#/]',ToMatch1)>0 OR PATINDEX('NO%',ToMatch1)>0 OR CHARINDEX('LEVEL',ToMatch1)>0 OR PATINDEX('%[0-9]%',ToMatch1)>0 OR CHARINDEX('BLOCK',ToMatch1)>0 OR CHARINDEX('LOT',ToMatch1)>0 OR PATINDEX('APART%NT',ToMatch1)>0 OR LEN(TRIM(ISNULL(ToMatch1,'')))=0) AND ((PATINDEX('%[0-9]%[^HD]',ToMatch2)>0 OR PATINDEX('[0-9]',ToMatch2)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch2)>0) AND LEN(ISNULL(ToMatch2,'')) BETWEEN 0 AND 7))
		OR (PATINDEX('%[0-9]%',ToMatch1)>0 AND (PATINDEX('%FL[OR]%',ToMatch2)>0 OR CHARINDEX('POST',ToMatch2)>0)) 
		OR (PATINDEX('PO%',ToMatch1)>0 AND PATINDEX('BOX%',ToMatch2)>0),12,
			IIF((PATINDEX('%[0-9]%[^HDL]',ToMatch1)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch1)>0 OR PATINDEX('%[0-9]/%',ToMatch1)>0) AND LEN(REPLACE(ToMatch1,',','')) BETWEEN 3 AND 6,1,0)) PrefixMatch,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #PrefixMatch_12_13)
--,STEP12_6 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE PrefixMatch WHEN 12 THEN TRIM(CONCAT(ToMatch1,' ',ToMatch2)) WHEN 1 THEN ToMatch1 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(ToConcat,''),' ',ISNULL(CASE WHEN PrefixMatch IN (12,1) THEN NULL ELSE ToMatch1 END,''))) ToConcat, --building terms removed from prefix3 field and concat with cleared Prefix2
	TRIM(CASE PrefixMatch WHEN 12 THEN NULL ELSE ToMatch2 END) ToMatch1, --building terms removed from prefix4 field
	Prefix15 ToMatch2,
	--Prefix13,
	--Prefix14,
	--Prefix15,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #PrefixMatch_13_14
FROM STEP12_5
DROP TABLE #PrefixMatch_12_13


--Prefix match on 14 and 15 prefix columns
;WITH STEP12_7 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	ToConcat,
	ToMatch1,
	ToMatch2,
	--Prefix13,
	--Prefix14,
	--Prefix15,
	IIF(
		((PATINDEX('[#/]',ToMatch1)>0 OR PATINDEX('NO%',ToMatch1)>0 OR CHARINDEX('LEVEL',ToMatch1)>0 OR PATINDEX('%[0-9]%',ToMatch1)>0 OR CHARINDEX('BLOCK',ToMatch1)>0 OR CHARINDEX('LOT',ToMatch1)>0 OR PATINDEX('APART%NT',ToMatch1)>0 OR LEN(TRIM(ISNULL(ToMatch1,'')))=0) AND ((PATINDEX('%[0-9]%[^HD]',ToMatch2)>0 OR PATINDEX('[0-9]',ToMatch2)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch2)>0) AND LEN(ISNULL(ToMatch2,'')) BETWEEN 0 AND 7))
		OR (PATINDEX('%[0-9]%',ToMatch1)>0 AND (PATINDEX('%FL[OR]%',ToMatch2)>0 OR CHARINDEX('POST',ToMatch2)>0)) 
		OR (PATINDEX('PO%',ToMatch1)>0 AND PATINDEX('BOX%',ToMatch2)>0),12,
			IIF((PATINDEX('%[0-9]%[^HDL]',ToMatch1)>0 OR PATINDEX('%[0-9]%[0-9,]',ToMatch1)>0 OR PATINDEX('%[0-9]/%',ToMatch1)>0) AND LEN(REPLACE(ToMatch1,',','')) BETWEEN 3 AND 6,1,0)) PrefixMatch, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #PrefixMatch_13_14)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE PrefixMatch WHEN 12 THEN TRIM(CONCAT(ToMatch1,' ',ToMatch2)) WHEN 1 THEN ToMatch1 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(ToConcat,''),' ',ISNULL(CASE WHEN PrefixMatch IN (12,1) THEN NULL ELSE ToMatch1 END,''))) ToConcat, --building terms removed from prefix3 field and concat with cleared Prefix2
	TRIM(CASE PrefixMatch WHEN 12 THEN NULL ELSE ToMatch2 END) ToMatch1, --building terms removed from prefix4 field
	--Prefix13,
	--Prefix14,
	--Prefix15,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #PrefixMatch_14_15
FROM STEP12_7
DROP TABLE #PrefixMatch_13_14


--Search and Seperation complete, finalize result into Building, Street, City field
;WITH Final AS 
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	TRIM(CONCAT(TRIM(ToConcat),' ',ISNULL(ToMatch1,''))) Street, --concat prefix14 with prefix15 as street
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #PrefixMatch_14_15)
,Final2 AS 
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	(SELECT TOP 1 [value]+CASE [value] WHEN 0 THEN 0 ELSE Increment END --find company names / building / apartments seperation point(index) from street
	FROM (SELECT PATINDEX('%FACTORY%',Street) [value],7 Increment UNION SELECT PATINDEX('%LTD%',Street) [value],3 Increment UNION 
		SELECT PATINDEX('%MANAGEMENT%',Street) [value],10 Increment UNION SELECT PATINDEX('%RESIDENT%',Street) [value],8 Increment UNION 
		SELECT PATINDEX('%HOUSE%',Street) [value],5 Increment UNION SELECT PATINDEX('%BUILDING%',Street) [value],8 Increment UNION
		SELECT PATINDEX('%BULDING%',Street) [value],7 Increment UNION SELECT PATINDEX('%BILDING%',Street) [value],7 Increment UNION
		SELECT PATINDEX('%BLDG%',Street) [value],4 Increment UNION SELECT PATINDEX('%DEP %',Street) [value],3 Increment UNION
		SELECT PATINDEX('%WTC %',Street) [value],3 Increment UNION SELECT PATINDEX('%BANK%',Street) [value],4 Increment UNION 
		SELECT PATINDEX('%CITY%',Street) [value],4 Increment UNION 
															--SELECT PATINDEX('%PARK%',Street) [value],4 Increment UNION 
		SELECT PATINDEX('%FACULTY%',Street) [value],7 Increment UNION SELECT PATINDEX('%COMPLEX%',Street) [value],7 Increment UNION
		SELECT PATINDEX('%DIVISION%',Street) [value],8 Increment UNION SELECT PATINDEX('%LIMITED%',Street) [value],7 Increment UNION
		SELECT PATINDEX('%PLC%',Street) [value],3 Increment UNION SELECT PATINDEX('%CENTRE%',Street) [value],6 Increment UNION
		SELECT PATINDEX('%CORPORATION%',Street) [value],11 Increment UNION SELECT PATINDEX('%BRANCH%',Street) [value],6 Increment UNION
		SELECT PATINDEX('%UNIT %',Street) [value],4 Increment UNION SELECT PATINDEX('%EXPORTS%',Street) [value],7 Increment UNION  
		SELECT PATINDEX('%ESTATE%',Street) [value],6 Increment UNION SELECT PATINDEX('%ESTAT%',Street) [value],5 Increment UNION
		SELECT PATINDEX('%ESTATE%',Street) [value],6 Increment UNION SELECT PATINDEX('%OFFICE%',Street) [value],6 Increment UNION
		SELECT PATINDEX('%APARTMENTS%',Street) [value],10 Increment UNION SELECT PATINDEX('%CEYLON%',Street) [value],6 Increment) T1
	ORDER BY [value] DESC) OtherSepIndex,
	Street,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM Final)
,Final3 AS( 
SELECT
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Original_City,
	Cleared_Address,
	TRIM(SUBSTRING(Street,0,OtherSepIndex+1)) BuildingOther,
	Building,
	TRIM(SUBSTRING(Street,OtherSepIndex+1,LEN(Street)+1)) Street,
	Cleared_City City,
	LEN(TRIM(Street)) StreetLen,
	Cleared_Addr_Contact,
	--CityMatchIndex,
	Contacts
FROM Final2)
SELECT * 
INTO #Final
FROM Final3

--SELECT *
--FROM #Final
--WHERE 
--LEN(TRIM(Street))<=30 

;WITH FINAL AS(
SELECT  
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Original_City,
	Cleared_Address,
	CASE WHEN REPLACE(BuildingOther,'.','') IN ('PVT LTD','(PVT) LTD') THEN '' ELSE  REPLACE(BuildingOther,'.','') END BuildingOther,
	Building,
	REPLACE(Street,REPLACE(ISNULL(BuildingOther,''),'.',''),'') Street, --replace duplicate building other values
	--Street,
	City,
	StreetLen,
	Cleared_Addr_Contact,
	Contacts
FROM #Final),
FINAL2 AS
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Original_City,
	(SELECT STRING_AGG(TRIM([value]),' ') FROM STRING_SPLIT((SELECT STRING_AGG(TRIM([value]),', ') FROM STRING_SPLIT(CONCAT(BuildingOther,' ',Building),',') WHERE TRIM([value])!=''),' ') WHERE TRIM([value])!='') Building,
	ISNULL((SELECT STRING_AGG(TRIM([value]),' ') FROM STRING_SPLIT((SELECT STRING_AGG(TRIM([value]),', ') FROM STRING_SPLIT(REPLACE(Street,'.',''),',') WHERE TRIM([value])!=''),' ') WHERE TRIM([value])!=''),'NA') Street,
	City,
	Cleared_Addr_Contact,
	Contacts
FROM FINAL)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Original_City,
	Building,
	Street,
	City,
	Cleared_Addr_Contact,
	Contacts
INTO #FINAL2
FROM FINAL2


SELECT 
	PickupId,
	F1.CustomerId,
	NewCus.NewCustomerId,
	CustomerName,
	AddGroup.AddressId,
	F1.Building,
	F1.Street,
	F1.City,
	--Cleared_Addr_Contact,
	F1.Contacts,
	CONCAT(P.SP_INSTRUCTIONS,CASE WHEN Cleared_Addr_Contact IS NULL THEN '' ELSE CONCAT(' / ',Cleared_Addr_Contact) END) SpInstructions, --append cleared addr contacts as SpInstructions
	P.PAYMENT_TYPE,
	P.PACKAGE_TYPE,
	P.ACTUAL_WEIGHT,
	P.AMOUNT,
	dbo.FnFixedTime(P.PICKUP_FROM,P.PICKUP_DATE,P.CREATED_DATE) PICKUP_FROM,
	dbo.FnFixedTime(P.PICKUP_TO,P.PICKUP_DATE,P.CREATED_DATE) PICKUP_TO,
	P.PICKUP_DATE,
	P.CREATED_BY,
	P.CREATED_DATE,
	P.MODIFIED_BY,
	P.MODIFIED_DATE,
	P.REMARKS,
	P.[STATUS]
INTO #FINAL3
FROM #FINAL2 F1 INNER JOIN (SELECT CustomerId,ROW_NUMBER() OVER(ORDER BY CustomerId) NewCustomerId 
	FROM #FINAL2 F1 GROUP BY CustomerId) NewCus
ON F1.CustomerId=NewCus.CustomerId INNER JOIN (SELECT CustomerId,ROW_NUMBER() OVER(ORDER BY CustomerId) AddressId,ISNULL(Building,'') Building,Street,City
	FROM #FINAL2 GROUP BY CustomerId,ISNULL(Building,''),Street,City) AddGroup
ON F1.CustomerId=AddGroup.CustomerId AND ISNULL(F1.Building,'')=AddGroup.Building
	AND F1.Street=AddGroup.Street AND F1.City=AddGroup.City INNER JOIN dbo.PICKUP P
ON F1.PickupId=P.PICKUP_ID 


DELETE FROM [FitsExpress_DispatchMgmtDB].dbo.ShipmentPickupCourier
DELETE FROM [FitsExpress_DispatchMgmtDB].dbo.ShipmentPickupPackage
DELETE FROM [FitsExpress_DispatchMgmtDB].dbo.ShipmentPickupSnapshot
DELETE FROM [FitsExpress_DispatchMgmtDB].dbo.ShipmentPickupTpdUpdate
DELETE FROM [FitsExpress_DispatchMgmtDB].dbo.ShipmentPickup
DELETE FROM [FitsExpress_DispatchMgmtDB].dbo.PickupCustomerContact
DELETE FROM [FitsExpress_DispatchMgmtDB].dbo.PickupCustomerAddress
DELETE FROM [FitsExpress_DispatchMgmtDB].dbo.PickupCustomer

SET IDENTITY_INSERT [FitsExpress_DispatchMgmtDB].dbo.PickupCustomer ON

INSERT INTO [FitsExpress_DispatchMgmtDB].dbo.PickupCustomer(CustomerId,CustomerName,OldAccountNo,CreatedBy,CreatedDate,ModifiedBy,ModifiedDate,RecStatus)
SELECT DISTINCT F3.NewCustomerId,F3.CustomerName,CU.ACCOUNT_NO,CU.CREATED_BY,CU.CREATED_DATE,CU.MODIFIED_BY,CU.MODIFIED_DATE,CU.[STATUS]
FROM #FINAL3 F3 INNER JOIN dbo.CUSTOMER CU
ON F3.CustomerId=CU.CUSTOMER_ID

SET IDENTITY_INSERT [FitsExpress_DispatchMgmtDB].dbo.PickupCustomer OFF


SET IDENTITY_INSERT [FitsExpress_DispatchMgmtDB].dbo.PickupCustomerAddress ON

INSERT INTO [FitsExpress_DispatchMgmtDB].dbo.PickupCustomerAddress(AddressId,CustomerId,Building,Street,City,Postal,Country,CreatedBy,CreatedDate,ModifiedBy,ModifiedDate,RecStatus)
SELECT DISTINCT F3.AddressId,F3.NewCustomerId,F3.Building,F3.Street,F3.City,NULL,'LK',CU.CREATED_BY,CU.CREATED_DATE,10001,GETDATE(),CU.[STATUS]
FROM #FINAL3 F3 INNER JOIN dbo.CUSTOMER CU
ON F3.CustomerId=CU.CUSTOMER_ID

SET IDENTITY_INSERT [FitsExpress_DispatchMgmtDB].dbo.PickupCustomerAddress OFF


SET IDENTITY_INSERT [FitsExpress_DispatchMgmtDB].dbo.ShipmentPickup ON

INSERT INTO  [FitsExpress_DispatchMgmtDB].dbo.ShipmentPickup(PickupId,CustomerId,AddressId,ContactPersId,PickupDate,PickupTimeFrom,PickupTimeTo,PaymentType,PaymentAmount,PackageType,PackageWeight,OldContacts,SpInstructions,CreatedBy,CreatedDate,ModifiedBy,ModifiedDate,RecRemarks,RecStatus)
SELECT DISTINCT F3.PickupId,F3.NewCustomerId,F3.AddressId,NULL,CONVERT(date,F3.PICKUP_DATE),F3.PICKUP_FROM,F3.PICKUP_TO,F3.PAYMENT_TYPE,F3.AMOUNT,F3.PACKAGE_TYPE,F3.ACTUAL_WEIGHT,F3.Contacts,F3.SpInstructions,CASE WHEN F3.CREATED_BY IN (0) THEN 10001 ELSE F3.CREATED_BY END,F3.CREATED_DATE,CASE WHEN F3.MODIFIED_BY IN (0) THEN 10001 ELSE F3.MODIFIED_BY END,F3.MODIFIED_DATE,F3.REMARKS,F3.[STATUS] --to be removed after app users migrated again
FROM #FINAL3 F3

SET IDENTITY_INSERT [FitsExpress_DispatchMgmtDB].dbo.ShipmentPickup OFF

SET IDENTITY_INSERT [FitsExpress_DispatchMgmtDB].dbo.ShipmentPickupCourier ON

INSERT INTO [FitsExpress_DispatchMgmtDB].dbo.ShipmentPickupCourier(CourPickupId,PickupId,CourAgentId,Density,ExceptionId,CreatedBy,CreatedDate,ModifiedBy,ModifiedDate,RecRemarks,RecStatus)
SELECT CP.[COURIER_PICK_ID]
      ,CP.[PICKUP_ID]
      ,CP.[CAGENT_ID]
	  ,NULL
      ,CP.[EXCEP_ID]
      ,CP.[CREATED_BY]
      ,CP.[CREATED_DATE]
      ,CP.[MODIFIED_BY]
      ,CP.[MODIFIED_DATE]
      ,CP.[REMARKS]
      ,CP.[STATUS]
  FROM .[dbo].[CPICKUP_INFO] CP

SET IDENTITY_INSERT [FitsExpress_DispatchMgmtDB].dbo.ShipmentPickupCourier OFF


INSERT INTO [FitsExpress_DispatchMgmtDB].dbo.ShipmentPickupPackage(PickupId,TrackingNumber)
SELECT [PICKUP_ID],[TRACKING_NO] FROM [dbo].[PICKUP_WAYBILL]

SET IDENTITY_INSERT [FitsExpress_DispatchMgmtDB].dbo.ShipmentPickupSnapshot ON

INSERT INTO [FitsExpress_DispatchMgmtDB].dbo.ShipmentPickupSnapshot(SnapshotId,PickupId,AtchmntData,RecStatus)
SELECT [SNAPSHOT_ID],[PICKUP_ID],[SNAPSHOTS],[STATUS]
FROM [dbo].[PICKUP_SNAPSHOT]

SET IDENTITY_INSERT [FitsExpress_DispatchMgmtDB].dbo.ShipmentPickupSnapshot OFF
--56804