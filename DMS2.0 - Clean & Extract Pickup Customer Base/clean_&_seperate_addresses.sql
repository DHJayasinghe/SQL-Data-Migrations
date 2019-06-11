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
		WHEN PATINDEX('%COL %',Cleared_Address)>0 THEN STUFF(Cleared_Address,PATINDEX('%COL %',Cleared_Address),3,'COLOMBO')
		WHEN PATINDEX('%CO %',Cleared_Address)>0 THEN STUFF(Cleared_Address,PATINDEX('%CO %',Cleared_Address),3,'COLOMBO')
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
--WHERE LEN(Filtered_Contact)>0
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
	--IIF(PATINDEX('% 00[0-9]',Cleared_Address)>0,STUFF(Cleared_Address,PATINDEX('% 00[0-9]',Cleared_Address)+1,1,''), --correct COLOMBO 002 like words to COLOMBO 02
	--IIF(PATINDEX('% 0[0-9]0',Cleared_Address)>0,STUFF(Cleared_Address,PATINDEX('% 0[0-9]0',Cleared_Address)+1,1,''),Cleared_Address)) Cleared_Address, --correct COLOMBO 010 like words to COLOMBO 10
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
DROP TABLE #tmpPickupAddresses5 --release memory

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
-- Clear Customer Name (if exists) from begining of the address field
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

--seperate cleared address field into prefixes, so can seperate building and street later
;WITH STEP8_1 AS
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	(SELECT STRING_AGG(TRIM([value]),', ') FROM STRING_SPLIT(Cleared_Address,',') WHERE TRIM([value])!='') Cleared_Address, --remove trailing and leading commas
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
	Cleared_Address,
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
	TRIM(REPLACE(Cleared_Address,Street,'')) Cleared_Address,
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
	(SELECT STRING_AGG([value],', ') FROM STRING_SPLIT(Prefix1,',') WHERE TRIM([value])!='') Prefix1,
	(SELECT STRING_AGG([value],', ') FROM STRING_SPLIT(Prefix2,',') WHERE TRIM([value])!='') Prefix2,
	(SELECT STRING_AGG([value],', ') FROM STRING_SPLIT(Prefix3,',') WHERE TRIM([value])!='') Prefix3,
	(SELECT STRING_AGG([value],', ') FROM STRING_SPLIT(Prefix4,',') WHERE TRIM([value])!='') Prefix4,
	(SELECT STRING_AGG([value],', ') FROM STRING_SPLIT(TRIM(IIF(CHARINDEX(' ', Prefix5)>0,SUBSTRING(Prefix5,1,CHARINDEX(' ', Prefix5)),Prefix5)),',') WHERE TRIM([value])!='') Prefix5,
	(SELECT STRING_AGG([value],', ') FROM STRING_SPLIT(TRIM(IIF(CHARINDEX(' ', Prefix5)>0,STUFF(Prefix5,1,CHARINDEX(' ', Prefix5),''),NULL)),',') WHERE TRIM([value])!='') Prefix6,
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


;WITH STEP9_1 AS
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Prefix1, 
	Prefix2,
	Prefix3,
	Prefix4,
	Prefix5,
	Prefix6,
	--compare prefix1 column and prefix2 column
	IIF(PATINDEX('%[0-9]%',Prefix2)>0 OR PATINDEX('F%R',Prefix2)>0 OR PATINDEX('%HOUSE%',Prefix2)>0 OR PATINDEX('CENT%',Prefix2)>0 OR PATINDEX('SECOND%',Prefix2)>0 OR PATINDEX('B%G',Prefix2)>0 OR PATINDEX('DEP%',Prefix2)>0,12, --like 3 1/1 | 4TH FLOOR | BLOCK 12 | MARITIME CENTER => 12
		IIF(PATINDEX('NO%',Prefix1)>0 OR PATINDEX('LEVEL%',Prefix1)>0 OR PATINDEX('%[0-9]%',Prefix1)>0  OR PATINDEX('BLOCK%',Prefix1)>0,1,0)) Pref12Match, -- if prefix2 is empty and prefix1 is contain numbers => 1, else => 0
	Street, 
	HasStreet,
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #tmpPickupAddresses10)
,STEP9_2 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	--Prefix1, 
	TRIM(CASE Pref12Match WHEN 12 THEN CONCAT(Prefix1,' ',Prefix2)  WHEN 1 THEN Prefix1 ELSE NULL END) Building, --prefix1 converted to building field
	TRIM(CASE Pref12Match WHEN 12 THEN NULL WHEN 1 THEN Prefix2 ELSE CONCAT(Prefix1,' ',Prefix2) END) Prefix2, --building terms removed from prefix2 field
	Prefix3,
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
FROM STEP9_1)
,STEP9_3 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	--Prefix1, 
	Building,
	Prefix2,
	Prefix3,
	Prefix4,
	Prefix5,
	Prefix6,
	--compare prefix2 column and prefix3 column
	IIF(PATINDEX('%[0-9]%',Prefix3)>0 OR PATINDEX('F%R',Prefix3)>0 OR PATINDEX('%HOUSE%',Prefix3)>0 OR PATINDEX('CENT%',Prefix3)>0 OR PATINDEX('SECOND%',Prefix3)>0 OR PATINDEX('B%G',Prefix3)>0 OR PATINDEX('DEP%',Prefix3)>0,12, --like 3 1/1 | 4TH FLOOR | BLOCK 12 | MARITIME CENTER => 12
		IIF(LEN(ISNULL(Prefix2,''))=0 OR PATINDEX('NO%',Prefix2)>0 OR PATINDEX('LEVEL%',Prefix2)>0 OR PATINDEX('%[0-9]%',Prefix2)>0 OR PATINDEX('BLOCK%',Prefix2)>0 OR  PATINDEX('APART%T',Prefix2)>0,1,0)) Pref23Match, -- if prefix3 is empty and prefix2 is contain numbers => 1, else => 0
	Street, 
	HasStreet,
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM STEP9_2)
,STEP9_4 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE Pref23Match WHEN 12 THEN CONCAT(Prefix2,' ',Prefix3) WHEN 1 THEN Prefix2 ELSE NULL END)) Building,
	--Prefix3,
	TRIM(CASE Pref23Match WHEN 0 THEN Prefix2 ELSE NULL END) Prefix2, --building terms removed from prefix2 field
	TRIM(CASE Pref23Match WHEN 12 THEN NULL ELSE Prefix3 END) Prefix3, --building terms removed from prefix3 field
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
FROM STEP9_3)
,STEP9_5 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	--Prefix1, 
	Building,
	Prefix2,
	Prefix3,
	Prefix4,
	Prefix5,
	Prefix6,
	--compare prefix3 column and prefix4 column
	IIF((PATINDEX('%[0-9]%',Prefix4)>0 OR PATINDEX('F%R',Prefix4)>0 OR PATINDEX('%HOUSE%',Prefix4)>0 OR PATINDEX('CENT%',Prefix4)>0 OR PATINDEX('SECOND%',Prefix4)>0 OR PATINDEX('B%G',Prefix4)>0 OR PATINDEX('DEP%',Prefix4)>0)  --like 3 1/1 | 4TH FLOOR | BLOCK 12 | MARITIME CENTER => 12
		AND (LEN(ISNULL(Prefix3,''))=0 OR PATINDEX('NO%',Prefix3)>0 OR PATINDEX('LEVEL%',Prefix3)>0 OR PATINDEX('%[0-9]%',Prefix3)>0  OR PATINDEX('BLOCK%',Prefix3)>0 OR PATINDEX('APART%T',Prefix3)>0 OR PATINDEX('[&/]%',Prefix3)>0),12,
		IIF(LEN(ISNULL(Prefix3,''))=0 OR PATINDEX('NO%',Prefix3)>0 OR PATINDEX('LEVEL%',Prefix3)>0 OR PATINDEX('%[0-9]%',Prefix3)>0  OR PATINDEX('BLOCK%',Prefix3)>0 OR PATINDEX('APART%T',Prefix3)>0 OR PATINDEX('[&/]%',Prefix3)>0,1,0)) Pref34Match,
		--IIF(PATINDEX('NO%',Prefix3)>0 OR PATINDEX('LEVEL%',Prefix3)>0 OR PATINDEX('%[0-9]%',Prefix3)>0  OR PATINDEX('BLOCK%',Prefix3)>0 OR PATINDEX('[&/]%',Prefix3)>0,1,
		--	IIF(PATINDEX('[0-9]%',Prefix4)>0 OR PATINDEX('F%R',Prefix4)>0 OR PATINDEX('%HOUSE%',Prefix4)>0 OR PATINDEX('CENT%',Prefix4)>0 OR PATINDEX('SECOND%',Prefix4)>0 OR PATINDEX('B%G',Prefix4)>0 OR PATINDEX('DEP%',Prefix4)>0,2,0))) Pref34Match, -- if prefix4 is empty and prefix3 is contain numbers => 1, else => 0
	Street, 
	HasStreet,
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM STEP9_4)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE Pref34Match WHEN 12 THEN CONCAT(Prefix3,' ',Prefix4) WHEN 1 THEN Prefix3 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(Prefix2,''),' ',ISNULL(CASE WHEN Pref34Match IN (12,1) THEN NULL ELSE Prefix3 END,''))) Prefix3, --building terms removed from prefix3 field and concat with cleared Prefix2
	TRIM(CASE Pref34Match WHEN 12 THEN NULL ELSE Prefix4 END) Prefix4, --building terms removed from prefix4 field
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
INTO #tmpPickupAddresses11 --save to memory simplify query expression table
FROM STEP9_5
--DROP TABLE #tmpPickupAddresses10


--SELECT * FROM #tmpPickupAddresses11 WHERE PickupId IN (10042,10043)
;WITH STEP9_7 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	CASE WHEN Prefix3='ROAD' THEN CONCAT(Cleared_City,' ',Prefix3) ELSE Prefix3 END Prefix3, --fix truncated road names during city name removal from address at begining, Ex: 286A RAJAGIRIYA ROAD, RAJAGIRIYA
	Prefix4, 
	Prefix5,
	Prefix6,
	--compare prefix4 column and prefix5 column
	IIF((PATINDEX('%[0-9]%',Prefix5)>0 OR PATINDEX('F%R%',Prefix5)>0 OR PATINDEX('%HOUSE%',Prefix5)>0 OR PATINDEX('CENT%',Prefix5)>0 OR PATINDEX('SECOND%',Prefix5)>0 OR PATINDEX('B%G',Prefix5)>0 OR PATINDEX('DEP%',Prefix5)>0)  --like 3 1/1 | 4TH FLOOR | BLOCK 12 | MARITIME CENTER => 12
		AND (LEN(ISNULL(Prefix4,''))=0 OR PATINDEX('NO%',Prefix4)>0 OR PATINDEX('LEVEL%',Prefix4)>0 OR PATINDEX('%[0-9]%',Prefix4)>0  OR PATINDEX('BLOCK%',Prefix4)>0 OR PATINDEX('APART%T',Prefix4)>0 OR PATINDEX('[&/]%',Prefix4)>0),12,
		IIF(LEN(ISNULL(Prefix4,''))=0 OR PATINDEX('NO%',Prefix4)>0 OR PATINDEX('LEVEL%',Prefix4)>0 OR PATINDEX('%[0-9]%',Prefix4)>0  OR PATINDEX('BLOCK%',Prefix4)>0 OR PATINDEX('APART%T',Prefix4)>0 OR PATINDEX('[&/]%',Prefix4)>0,1,0)) Pref45Match,
		--IIF(PATINDEX('NO%',Prefix4)>0 OR PATINDEX('LEVEL%',Prefix4)>0 OR PATINDEX('%[0-9]%',Prefix4)>0  OR PATINDEX('BLOCK%',Prefix4)>0 OR PATINDEX('[&/]%',Prefix4)>0,1,
		--IIF(PATINDEX('[0-9]%',Prefix5)>0 OR PATINDEX('F%R%',Prefix5)>0 OR PATINDEX('%HOUSE%',Prefix5)>0 OR PATINDEX('CENT%',Prefix5)>0 OR PATINDEX('SECOND%',Prefix5)>0 OR PATINDEX('B%G',Prefix5)>0 OR PATINDEX('DEP%',Prefix5)>0,2,0))) Pref45Match, -- if prefix5 is empty and prefix4 is contain numbers => 1, else => 0
	Street, 
	HasStreet,
	Seperated_Addr_Prefix, 
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #tmpPickupAddresses11)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE Pref45Match WHEN 12 THEN CONCAT(Prefix4,' ',Prefix5) WHEN 1 THEN Prefix4 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(Prefix3,''),' ',ISNULL(CASE WHEN Pref45Match IN (12,1) THEN NULL ELSE Prefix4 END,''))) Prefix4, --building terms removed from prefix4 field and concat with cleared Prefix2
	TRIM(CASE Pref45Match WHEN 12 THEN NULL ELSE Prefix5 END) Prefix5, --building terms removed from prefix5 field
	--Prefix5,
	TRIM(CONCAT(ISNULL(Prefix6,''),' ',TRIM(CONCAT(ISNULL(Street,''),' ',Seperated_Addr_Prefix)))) Prefix6, --move street field and seperated_addr_prefix field to prefix6 for filter
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #tmpPickupAddresses12
FROM STEP9_7

--SELECT * FROM #tmpPickupAddresses12 WHERE PickupId IN (10042,10043)
--seperate prefix6 into further more prefixes
;WITH SETP10_1 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	Prefix4,
	Prefix5,
	TRIM(IIF(CHARINDEX(' ', Prefix6)>0,SUBSTRING(Prefix6,1,CHARINDEX(' ', Prefix6)),Prefix6)) Prefix6, -- seperate remain address field by spaces
	TRIM(IIF(CHARINDEX(' ', Prefix6)>0,STUFF(Prefix6,1,CHARINDEX(' ', Prefix6),''),NULL)) Prefix7,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #tmpPickupAddresses12)
,SETP10_2 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	Prefix4,
	Prefix5,
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
	Prefix4,
	Prefix5,
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
	Prefix4,
	Prefix5,
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
	Prefix4,
	Prefix5,
	Prefix6,
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


--SELECT * FROM #tmpPickupAddresses13 WHERE PickupId IN (10042,10043)
;WITH STEP11_1 AS
(SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	Prefix4,
	Prefix5,
	Prefix6,
	Prefix7,
	Prefix8,
	Prefix9,
	Prefix10,
	Prefix11,
	IIF((PATINDEX('%[0-9]%',Prefix6)>0 OR PATINDEX('F%R%',Prefix6)>0 OR PATINDEX('%HOUSE%',Prefix6)>0 OR PATINDEX('CENT%',Prefix6)>0 OR PATINDEX('SECOND%',Prefix6)>0 OR PATINDEX('B%G',Prefix6)>0 OR PATINDEX('DEP%',Prefix6)>0)  --like 3 1/1 | 4TH FLOOR | BLOCK 12 | MARITIME CENTER => 12
		AND (LEN(ISNULL(Prefix5,''))=0 OR PATINDEX('NO%',Prefix5)>0 OR PATINDEX('LEVEL%',Prefix5)>0 OR PATINDEX('%[0-9]%',Prefix5)>0  OR PATINDEX('BLOCK%',Prefix5)>0 OR PATINDEX('APART%T',Prefix5)>0 OR PATINDEX('[&/]%',Prefix5)>0),12,
		IIF(LEN(ISNULL(Prefix5,''))=0 OR PATINDEX('NO%',Prefix5)>0 OR PATINDEX('LEVEL%',Prefix5)>0 OR PATINDEX('%[0-9]%',Prefix5)>0  OR PATINDEX('BLOCK%',Prefix5)>0 OR PATINDEX('APART%T',Prefix5)>0 OR PATINDEX('[&/]%',Prefix5)>0,1,0)) Pref56Match,
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
	TRIM(CONCAT(Building,' ',CASE Pref56Match WHEN 12 THEN CONCAT(Prefix5,' ',Prefix6) WHEN 1 THEN Prefix5 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(Prefix4,''),' ',ISNULL(CASE WHEN Pref56Match IN (12,1) THEN NULL ELSE Prefix5 END,''))) Prefix5, --building terms removed from prefix4 field and concat with cleared Prefix2
	TRIM(CASE Pref56Match WHEN 12 THEN NULL ELSE Prefix6 END) Prefix6, --building terms removed from prefix5 field
	Prefix7,
	Prefix8,
	Prefix9,
	Prefix10,
	Prefix11,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #tmpPickupAddresses14
FROM STEP11_1
--)

;WITH STEP11_3 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	Prefix5,
	Prefix6,
	Prefix7,
	Prefix8,
	Prefix9,
	Prefix10,
	Prefix11,
	IIF((PATINDEX('%[0-9]%',Prefix7)>0 OR PATINDEX('F%R%',Prefix7)>0 OR PATINDEX('%HOUSE%',Prefix7)>0 OR PATINDEX('CENT%',Prefix7)>0 OR PATINDEX('SECOND%',Prefix7)>0 OR PATINDEX('B%G',Prefix7)>0 OR PATINDEX('DEP%',Prefix7)>0)  --like 3 1/1 | 4TH FLOOR | BLOCK 12 | MARITIME CENTER => 12
		AND (LEN(ISNULL(Prefix6,''))=0 OR PATINDEX('NO%',Prefix6)>0 OR PATINDEX('LEVEL%',Prefix6)>0 OR PATINDEX('%[0-9]%',Prefix6)>0  OR PATINDEX('BLOCK%',Prefix6)>0 OR PATINDEX('APART%T',Prefix6)>0 OR PATINDEX('[&/]%',Prefix6)>0),12,
		IIF(LEN(ISNULL(Prefix6,''))=0 OR PATINDEX('NO%',Prefix6)>0 OR PATINDEX('LEVEL%',Prefix6)>0 OR PATINDEX('%[0-9]%',Prefix6)>0  OR PATINDEX('BLOCK%',Prefix6)>0 OR PATINDEX('APART%T',Prefix6)>0 OR PATINDEX('[&/]%',Prefix6)>0,1,0)) Pref67Match,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #tmpPickupAddresses14)
,STEP11_4 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE Pref67Match WHEN 12 THEN CONCAT(Prefix6,' ',Prefix7) WHEN 1 THEN Prefix6 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(Prefix5,''),' ',ISNULL(CASE WHEN Pref67Match IN (12,1) THEN NULL ELSE Prefix6 END,''))) Prefix6, --building terms removed from prefix4 field and concat with cleared Prefix2
	TRIM(CASE Pref67Match WHEN 12 THEN NULL ELSE Prefix7 END) Prefix7, --building terms removed from prefix5 field
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
FROM STEP11_3)
,STEP11_5 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	Prefix6,
	Prefix7,
	Prefix8,
	Prefix9,
	Prefix10,
	Prefix11,
	IIF((PATINDEX('%[0-9]%',Prefix8)>0 OR PATINDEX('F%R%',Prefix8)>0 OR PATINDEX('%HOUSE%',Prefix8)>0 OR PATINDEX('CENT%',Prefix8)>0 OR PATINDEX('SECOND%',Prefix8)>0 OR PATINDEX('B%G',Prefix8)>0 OR PATINDEX('DEP%',Prefix8)>0)  --like 3 1/1 | 4TH FLOOR | BLOCK 12 | MARITIME CENTER => 12
		AND (LEN(ISNULL(Prefix7,''))=0 OR PATINDEX('NO%',Prefix7)>0 OR PATINDEX('LEVEL%',Prefix7)>0 OR PATINDEX('%[0-9]%',Prefix7)>0  OR PATINDEX('BLOCK%',Prefix7)>0 OR PATINDEX('APART%T',Prefix7)>0 OR PATINDEX('[&/]%',Prefix7)>0),12,
		IIF(LEN(ISNULL(Prefix7,''))=0 OR PATINDEX('NO%',Prefix7)>0 OR PATINDEX('LEVEL%',Prefix7)>0 OR PATINDEX('%[0-9]%',Prefix7)>0  OR PATINDEX('BLOCK%',Prefix7)>0 OR PATINDEX('APART%T',Prefix7)>0 OR PATINDEX('[&/]%',Prefix7)>0,1,0)) Pref78Match,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM STEP11_4)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE Pref78Match WHEN 12 THEN CONCAT(Prefix7,' ',Prefix8) WHEN 1 THEN Prefix7 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(Prefix6,''),' ',ISNULL(CASE WHEN Pref78Match IN (12,1) THEN NULL ELSE Prefix7 END,''))) Prefix7, --building terms removed from prefix4 field and concat with cleared Prefix2
	TRIM(CASE Pref78Match WHEN 12 THEN NULL ELSE Prefix8 END) Prefix8, --building terms removed from prefix5 field
	--Prefix8,
	Prefix9,
	Prefix10,
	Prefix11,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #tmpPickupAddresses15
FROM STEP11_5

--release memory
DROP TABLE #tmpPickupAddresses10
DROP TABLE #tmpPickupAddresses11
DROP TABLE #tmpPickupAddresses12
DROP TABLE #tmpPickupAddresses13
DROP TABLE #tmpPickupAddresses14

;WITH STEP11_7 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	Prefix7,
	Prefix8,
	Prefix9,
	Prefix10,
	Prefix11,
	IIF((PATINDEX('%[0-9]%',Prefix9)>0 OR PATINDEX('F%R%',Prefix9)>0 OR PATINDEX('%HOUSE%',Prefix9)>0 OR PATINDEX('CENT%',Prefix9)>0 OR PATINDEX('SECOND%',Prefix9)>0 OR PATINDEX('B%G',Prefix9)>0 OR PATINDEX('DEP%',Prefix9)>0)  --like 3 1/1 | 4TH FLOOR | BLOCK 12 | MARITIME CENTER => 12
		AND (LEN(ISNULL(Prefix8,''))=0 OR PATINDEX('NO%',Prefix8)>0 OR PATINDEX('LEVEL%',Prefix8)>0 OR PATINDEX('%[0-9]%',Prefix8)>0  OR PATINDEX('BLOCK%',Prefix8)>0 OR PATINDEX('APART%T',Prefix9)>0 OR PATINDEX('[&/]%',Prefix8)>0),12,
		IIF(LEN(ISNULL(Prefix8,''))=0 OR PATINDEX('NO%',Prefix8)>0 OR PATINDEX('LEVEL%',Prefix8)>0 OR PATINDEX('%[0-9]%',Prefix8)>0  OR PATINDEX('BLOCK%',Prefix8)>0 OR PATINDEX('APART%T',Prefix9)>0 OR PATINDEX('[&/]%',Prefix8)>0,1,0)) Pref89Match,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #tmpPickupAddresses15)
,STEP11_8 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE Pref89Match WHEN 12 THEN CONCAT(Prefix8,' ',Prefix9) WHEN 1 THEN Prefix8 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(Prefix7,''),' ',ISNULL(CASE WHEN Pref89Match IN (12,1) THEN NULL ELSE Prefix8 END,''))) Prefix8, --building terms removed from prefix4 field and concat with cleared Prefix2
	TRIM(CASE Pref89Match WHEN 12 THEN NULL ELSE Prefix9 END) Prefix9, --building terms removed from prefix5 field
	--Prefix9,
	Prefix10,
	Prefix11,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM STEP11_7)
,STEP11_9 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	Prefix8,
	Prefix9,
	Prefix10,
	Prefix11,
	IIF((PATINDEX('%[0-9]%',Prefix10)>0 OR PATINDEX('F%R%',Prefix10)>0 OR PATINDEX('%HOUSE%',Prefix10)>0 OR PATINDEX('CENT%',Prefix10)>0 OR PATINDEX('SECOND%',Prefix10)>0 OR PATINDEX('B%G',Prefix10)>0 OR PATINDEX('DEP%',Prefix10)>0)  --like 3 1/1 | 4TH FLOOR | BLOCK 12 | MARITIME CENTER => 12
		AND (LEN(ISNULL(Prefix9,''))=0 OR PATINDEX('NO%',Prefix9)>0 OR PATINDEX('LEVEL%',Prefix9)>0 OR PATINDEX('%[0-9]%',Prefix9)>0  OR PATINDEX('BLOCK%',Prefix9)>0 OR PATINDEX('APART%T',Prefix9)>0 OR PATINDEX('[&/]%',Prefix9)>0),12,
		IIF(LEN(ISNULL(Prefix9,''))=0 OR PATINDEX('NO%',Prefix9)>0 OR PATINDEX('LEVEL%',Prefix9)>0 OR PATINDEX('%[0-9]%',Prefix9)>0  OR PATINDEX('BLOCK%',Prefix9)>0 OR PATINDEX('APART%T',Prefix9)>0 OR PATINDEX('[&/]%',Prefix9)>0,1,0)) Pref910Match,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM STEP11_8)
--,STEP11_10 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE Pref910Match WHEN 12 THEN CONCAT(Prefix9,' ',Prefix10) WHEN 1 THEN Prefix9 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(Prefix8,''),' ',ISNULL(CASE WHEN Pref910Match IN (12,1) THEN NULL ELSE Prefix9 END,''))) Prefix9, --building terms removed from prefix4 field and concat with cleared Prefix2
	TRIM(CASE Pref910Match WHEN 12 THEN NULL ELSE Prefix10 END) Prefix10, --building terms removed from prefix5 field
	--Prefix10,
	Prefix11,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
INTO #tmpPickupAddresses16
FROM STEP11_9
--)
;WITH STEP11_11 AS(
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	Building,
	Prefix9,
	Prefix10,
	Prefix11,
	IIF((PATINDEX('%[0-9]%',Prefix11)>0 OR PATINDEX('F%R%',Prefix11)>0 OR PATINDEX('%HOUSE%',Prefix11)>0 OR PATINDEX('CENT%',Prefix11)>0 OR PATINDEX('SECOND%',Prefix11)>0 OR PATINDEX('B%G',Prefix11)>0 OR PATINDEX('DEP%',Prefix11)>0)  --like 3 1/1 | 4TH FLOOR | BLOCK 12 | MARITIME CENTER => 12
		AND (LEN(ISNULL(Prefix10,''))=0 OR PATINDEX('NO%',Prefix10)>0 OR PATINDEX('LEVEL%',Prefix10)>0 OR PATINDEX('%[0-9]%',Prefix10)>0  OR PATINDEX('BLOCK%',Prefix10)>0 OR PATINDEX('APART%T',Prefix10)>0 OR PATINDEX('[&/]%',Prefix10)>0),12,
		IIF(LEN(ISNULL(Prefix10,''))=0 OR PATINDEX('NO%',Prefix10)>0 OR PATINDEX('LEVEL%',Prefix10)>0 OR PATINDEX('%[0-9]%',Prefix10)>0  OR PATINDEX('BLOCK%',Prefix10)>0 OR PATINDEX('APART%T',Prefix10)>0 OR PATINDEX('[&/]%',Prefix10)>0,1,0)) Pref1011Match,
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
FROM #tmpPickupAddresses16)
SELECT 
	PickupId,
	CustomerId,
	CustomerName,
	Original_Address,
	Cleared_Address,
	TRIM(CONCAT(Building,' ',CASE Pref1011Match WHEN 12 THEN CONCAT(Prefix10,' ',Prefix11) WHEN 1 THEN Prefix10 ELSE NULL END)) Building,
	TRIM(CONCAT(ISNULL(Prefix9,''),' ',ISNULL(CASE WHEN Pref1011Match IN (12,1) THEN NULL ELSE Prefix10 END,''))) Prefix10, --building terms removed from prefix4 field and concat with cleared Prefix2
	TRIM(CASE Pref1011Match WHEN 12 THEN NULL ELSE Prefix11 END) Prefix11, --building terms removed from prefix5 field
	Cleared_Addr_Contact,
	Original_City,
	Cleared_City,
	CityMatchIndex,
	Contacts
--INTO #tmpPickupAddresses17
FROM STEP11_11
--DROP TABLE #tmpPickupAddresses16

--SELECT * FROM #tmpPickupAddresses15
--WHERE Prefix11 IS NOT NULL
--WHERE PickupId IN (10042,10043)

--DROP TABLE #tmpPickupAddresses15


/*
CREATE function [dbo].[SplitIntoFixedLength] (
 @string nvarchar(max),
 @stringlength int
) returns @list table (
 word nvarchar(max)
)
as
begin
	-- sql function begins
	if len(@string) > 0 and @stringlength > 0
	begin
		declare @inverse_string nvarchar(max)=REVERSE(@string)	
		declare @i int -- character index
		set @i = 1

		while @i <= len(@string)
		begin
			if @stringlength=1
				insert into @list(word) select word from 
				(select SUBSTRING(@string,@i,@stringlength) word) T1 
				WHERE word NOT IN (SELECT word FROM @list)
			ELSE
				insert into @list(word) SELECT word from
				(select SUBSTRING(@string,@i,@stringlength) word UNION ALL
				select SUBSTRING(@inverse_string,@i,@stringlength) word) T1
				WHERE word NOT IN (SELECT word FROM @list)
			set @i = @i + @stringlength
		end
	end
	return
end
GO
*/

